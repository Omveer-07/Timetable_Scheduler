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

class FacultyScheduleScreen extends StatefulWidget {
  const FacultyScheduleScreen({super.key, this.profile});

  final AppUserProfile? profile;

  @override
  State<FacultyScheduleScreen> createState() => _FacultyScheduleScreenState();
}

class _FacultyScheduleScreenState extends State<FacultyScheduleScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TimetableService _timetableService = TimetableService();
  final TimetableNameResolver _nameResolver = TimetableNameResolver();
  final BasicInformationService _basicInfoService = BasicInformationService();

  List<String> _headers = [];

  List<String> _dayNames = List<String>.from(_defaultDays);
  List<Map<String, dynamic>> _faculties = [];
  String? _selectedFacultyId;
  bool _loadingFaculties = true;
  bool _loadingSchedule = false;
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
    await _loadFaculties();
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

    return headers;
  }

  List<int> _getBreakIndexes() {
    final indexes = <int>[];

    for (int i = 0; i < _headers.length; i++) {
      if (_headers[i].toUpperCase().contains('BREAK')) {
        indexes.add(i);
      }
    }

    return indexes;
  }

  Future<void> _loadFaculties() async {
    setState(() {
      _loadingFaculties = true;
      _errorMessage = null;
    });

    try {
      final facultySnapshot = await _firstNonEmpty(['faculty', 'Faculty']);
      if (!mounted) return;

      final faculties = facultySnapshot.docs
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
        _faculties = faculties;
        _dayNames = dayNames.isNotEmpty ? dayNames : _defaultDays;
        _periodsPerDay = _headers.isNotEmpty ? _headers.length : periods;
        _grid = TimetableFirestoreHelpers.emptyGridForDays(
          orderedDayNames: _dayNames,
          periodsPerDay: _headers.isNotEmpty ? _headers.length : periods,
        );
        _selectedFacultyId = faculties.isNotEmpty
            ? faculties.first['id'] as String
            : null;
      });

      if (_selectedFacultyId != null) {
        await getTimetableByFaculty(_selectedFacultyId!);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load faculties. Check your connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingFaculties = false;
        });
      }
    }
  }

  Future<void> getTimetableByFaculty(String facultyId) async {
    setState(() {
      _loadingSchedule = true;
      _errorMessage = null;
      _grid = TimetableFirestoreHelpers.emptyGridForDays(
        orderedDayNames: _dayNames,
        periodsPerDay: _periodsPerDay,
      );
    });

    try {
      final timetableSnapshot = await _db
          .collection('timetable')
          .where('faculty_id', isEqualTo: facultyId)
          .where('status', isEqualTo: 'published')
          .get();

      if (!mounted) return;

      if (timetableSnapshot.docs.isEmpty) {
        setState(() {
          _loadingSchedule = false;
        });
        return;
      }

      final subjectIds = <String>{};
      final programIds = <String>{};
      final roomIds = <String>{};

      for (final doc in timetableSnapshot.docs) {
        final data = doc.data();
        final subjectId = (data['subject_id'] ?? '').toString();
        final programId = (data['program_id'] ?? '').toString();
        final roomId = (data['room_id'] ?? '').toString();
        if (subjectId.isNotEmpty) subjectIds.add(subjectId);
        if (programId.isNotEmpty) programIds.add(programId);
        if (roomId.isNotEmpty) roomIds.add(roomId);
      }

      final names = await _nameResolver.resolve(
        subjectIds: subjectIds,
        facultyIds: const {},
        roomIds: roomIds,
        programIds: programIds,
      );

      if (!mounted) return;

      final nextGrid = TimetableFirestoreHelpers.buildFacultyViewGrid(
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
          _errorMessage = 'Failed to load schedule from Firestore.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingSchedule = false;
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
        title: const Text('Faculty Schedule'),
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
              'Weekly Faculty Schedule',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const Text(
              'Subject · Program · Room',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedFacultyId,
                  decoration: const InputDecoration(
                    labelText: 'Select Faculty',
                    border: OutlineInputBorder(),
                  ),
                  items: _faculties
                      .map(
                        (faculty) => DropdownMenuItem<String>(
                          value: faculty['id'] as String,
                          child: Text(
                            (faculty['faculty_name'] ??
                                    faculty['full_name'] ??
                                    faculty['id'])
                                .toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingFaculties
                      ? null
                      : (value) async {
                          if (value == null) return;
                          setState(() {
                            _selectedFacultyId = value;
                          });
                          await getTimetableByFaculty(value);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingFaculties || _loadingSchedule)
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
            else if (_selectedFacultyId == null)
              const Expanded(child: Center(child: Text('No faculty available')))
            else if (_isGridEmpty)
              const Expanded(
                child: Center(
                  child: Text('No classes scheduled for this faculty yet.'),
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
                        mode: TimetableGridMode.facultyView,
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
