import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timetable_scheduler/models/app_user_profile.dart';
import 'package:timetable_scheduler/routes/app_routes.dart';
import 'package:timetable_scheduler/services/basic_information_service.dart';
import 'package:timetable_scheduler/models/schedule_slot.dart';
import 'package:timetable_scheduler/services/timetable_firestore_helpers.dart';
import 'package:timetable_scheduler/services/timetable_name_resolver.dart';
import 'package:timetable_scheduler/services/timetable_service.dart';
import 'package:timetable_scheduler/widgets/logout_app_bar_action.dart';
import 'package:timetable_scheduler/widgets/timetable_grid.dart';

class ViewTimetableScreen extends StatefulWidget {
  const ViewTimetableScreen({super.key, this.profile});

  final AppUserProfile? profile;

  @override
  State<ViewTimetableScreen> createState() => _ViewTimetableScreenState();
}

class _ViewTimetableScreenState extends State<ViewTimetableScreen> {
  final BasicInformationService _basicInfoService = BasicInformationService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TimetableService _timetableService = TimetableService();
  final TimetableNameResolver _nameResolver = TimetableNameResolver();

  List<String> _headers = [];

  List<String> _dayNames = List<String>.from(_defaultDays);
  List<Map<String, dynamic>> _programs = [];
  String? _selectedProgramId;
  bool _loadingPrograms = true;
  bool _loadingTimetable = false;
  String? _errorMessage;
  int _periodsPerDay = 6;

  Map<String, List<Map<String, dynamic>?>> _grid = {};

  static const List<String> _defaultDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadHeaders();
    await _loadPrograms();
  }

  Future<List<String>> _loadHeaders() async {
    final info = await _basicInfoService.load();

    if (info == null) {
      return [];
    }

    final headers = <String>[];

    for (final period in info.periods) {
      headers.add(
        '${ScheduleSlot.formatMinutes(period.startMinutes)}-'
        '${ScheduleSlot.formatMinutes(period.endMinutes)}',
      );

      for (final br in info.breaks) {
        if (br.startMinutes == period.endMinutes) {
          headers.add(br.name.toUpperCase());
        }
      }
    }

    setState(() {
      _headers = headers;
    });

    print('HEADERS = $_headers');
    print('COUNT = ${_headers.length}');

    return headers;
  }

  Future<void> _loadPrograms() async {
    setState(() {
      _loadingPrograms = true;
      _errorMessage = null;
    });

    try {
      final programsSnapshot = await _firstNonEmpty(['programs', 'Programs']);

      if (!mounted) return;

      final programs = programsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      final dayNames = await _timetableService.getWorkingDayNames();
      if (!mounted) return;

      final configDoc = await _db.collection('config').doc('timetable').get();
      if (!mounted) return;

      final periods =
          (configDoc.data()?['periods_per_day'] as num?)?.toInt() ??
          (configDoc.data()?['periods'] as num?)?.toInt() ??
          6;

      setState(() {
        _programs = programs;
        _dayNames = dayNames.isNotEmpty ? dayNames : _defaultDays;
        _periodsPerDay = _headers.isNotEmpty ? _headers.length : periods;
        _grid = TimetableFirestoreHelpers.emptyGridForDays(
          orderedDayNames: _dayNames,
          periodsPerDay: _headers.isNotEmpty ? _headers.length : periods,
        );
        _selectedProgramId = programs.isNotEmpty
            ? programs.first['id'] as String
            : null;
      });

      if (_selectedProgramId != null) {
        await getTimetableByProgram(_selectedProgramId!);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load programs. Check your connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPrograms = false;
        });
      }
    }
  }

  /// ADD THIS NEW METHOD
  List<int> _getBreakIndexes() {
    final indexes = <int>[];

    for (int i = 0; i < _headers.length; i++) {
      if (_headers[i].toUpperCase().contains('BREAK')) {
        indexes.add(i);
      }
    }

    return indexes;
  }

  Future<void> getTimetableByProgram(String programId) async {
    setState(() {
      _loadingTimetable = true;
      _errorMessage = null;
      _grid = TimetableFirestoreHelpers.emptyGridForDays(
        orderedDayNames: _dayNames,
        periodsPerDay: _periodsPerDay,
      );
    });

    try {
      final timetableSnapshot = await _db
          .collection('timetable')
          .where('program_id', isEqualTo: programId)
          .where('status', isEqualTo: 'published')
          .get();

      if (!mounted) return;

      if (timetableSnapshot.docs.isEmpty) {
        setState(() {
          _loadingTimetable = false;
        });
        return;
      }

      final subjectIds = <String>{};
      final facultyIds = <String>{};
      final roomIds = <String>{};

      for (final doc in timetableSnapshot.docs) {
        final data = doc.data();
        final subjectId = (data['subject_id'] ?? '').toString();
        final facultyId = (data['faculty_id'] ?? '').toString();
        final roomId = (data['room_id'] ?? '').toString();
        if (subjectId.isNotEmpty) subjectIds.add(subjectId);
        if (facultyId.isNotEmpty) facultyIds.add(facultyId);
        if (roomId.isNotEmpty) roomIds.add(roomId);
      }

      final names = await _nameResolver.resolve(
        subjectIds: subjectIds,
        facultyIds: facultyIds,
        roomIds: roomIds,
      );

      if (!mounted) return;

      final nextGrid = TimetableFirestoreHelpers.buildProgramViewGrid(
        docs: timetableSnapshot.docs,
        orderedDayNames: _dayNames,
        periodsPerDay: _periodsPerDay,
        names: names,
        breakIndexes: _getBreakIndexes(),
      );

      setState(() {
        _grid = nextGrid;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load timetable from Firestore.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingTimetable = false;
        });
      }
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _firstNonEmpty(
    List<String> collections,
  ) async {
    QuerySnapshot<Map<String, dynamic>>? fallback;
    for (final collection in collections) {
      final snapshot = await _db.collection(collection).get();
      fallback ??= snapshot;
      if (snapshot.docs.isNotEmpty) {
        return snapshot;
      }
    }
    return fallback ?? await _db.collection(collections.first).get();
  }

  bool get _isGridEmpty => TimetableFirestoreHelpers.isGridEmpty(_grid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Timetable'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.calendar),
          ),
          const LogoutAppBarAction(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly Student Timetable',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedProgramId,
                  decoration: const InputDecoration(
                    labelText: 'Select Program',
                    border: OutlineInputBorder(),
                  ),
                  items: _programs
                      .map(
                        (program) => DropdownMenuItem<String>(
                          value: program['id'] as String,
                          child: Text(
                            (program['program_name'] ??
                                    program['name'] ??
                                    program['id'])
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingPrograms
                      ? null
                      : (value) async {
                          if (value == null) return;
                          setState(() {
                            _selectedProgramId = value;
                          });
                          await getTimetableByProgram(value);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingPrograms || _loadingTimetable)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_errorMessage!, textAlign: TextAlign.center),
                  ),
                ),
              )
            else if (_selectedProgramId == null)
              const Expanded(
                child: Center(child: Text('No programs available')),
              )
            else if (_isGridEmpty)
              const Expanded(
                child: Center(
                  child: Text('No timetable for this program yet.'),
                ),
              )
            else
              Expanded(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: TimetableGrid(
                        days: _dayNames,
                        periodsPerDay: _periodsPerDay,
                        headers: _headers,
                        grid: _grid,
                        mode: TimetableGridMode.programView,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
