import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;
import 'package:timetable_scheduler/utils/room_type_utils.dart';
import 'package:timetable_scheduler/services/basic_information_service.dart';

class TimetableService {
  TimetableService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int periodsPerLabSession = 2;

  static const List<String> _programCollections = ['programs', 'Programs'];

  static const List<String> _subjectCollections = ['subjects', 'Subjects'];

  static const List<String> _mappingCollections = ['mappings', 'Mappings'];

  static const List<String> _roomCollections = ['rooms', 'Rooms', 'Room'];

  static const List<Map<String, String>> _configCandidates = [
    {'collection': 'config', 'doc': 'timetable'},
    {'collection': 'Config', 'doc': 'timetable'},
    {'collection': 'timetable_config', 'doc': 'default'},
  ];

  Future<List<Map<String, dynamic>>> getAllPrograms() async {
    try {
      final docs = await _getDocsFromCandidates(_programCollections);

      return docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false);
    } catch (e, st) {
      dev.log('getAllPrograms failed', error: e, stackTrace: st);
      return [];
    }
  }
  Future<List<Map<String, dynamic>>> getSubjectsByProgram(
    String programId,
  ) async {
    if (programId.isEmpty) {
      return [];
    }

    try {
      final docs = await _getDocsFromCandidates(_subjectCollections);

      return docs
          .where((doc) => (doc.data()['program_id'] ?? '') == programId)
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false);
    } catch (e, st) {
      dev.log('getSubjectsByProgram failed', error: e, stackTrace: st);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMappings() async {
    try {
      final docs = await _getDocsFromCandidates(_mappingCollections);

      return docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false);
    } catch (e, st) {
      dev.log('getMappings failed', error: e, stackTrace: st);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRooms() async {
    try {
      final docs = await _getDocsFromCandidates(_roomCollections);

      return docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false);
    } catch (e, st) {
      dev.log('getRooms failed', error: e, stackTrace: st);
      return [];
    }
  }

  Future<Map<String, dynamic>> getConfig() async {
    try {
      for (final candidate in _configCandidates) {
        final doc = await _db
            .collection(candidate['collection']!)
            .doc(candidate['doc']!)
            .get();

        if (doc.exists) {
          final data = doc.data() ?? {};

          return {
            'working_days_per_week':
                (data['working_days_per_week'] as num?)?.toInt() ??
                (data['working_days'] as num?)?.toInt() ??
                5,

            'periods_per_day':
                (data['periods_per_day'] as num?)?.toInt() ??
                (data['periods'] as num?)?.toInt() ??
                6,

            'duration_per_period':
                (data['duration_per_period'] as num?)?.toInt() ?? 50,

            'max_lectures_per_day':
                (data['max_lectures_per_day'] as num?)?.toInt() ?? 4,
          };
        }
      }
    } catch (e, st) {
      dev.log('getConfig failed', error: e, stackTrace: st);
    }

    return {
      'working_days_per_week': 5,
      'periods_per_day': 6,
      'duration_per_period': 50,
      'max_lectures_per_day': 4,
    };
  }

  Future<Map<String, dynamic>> createEmptyTimetableGrid() async {
    try {
      final config = await getConfig();
      final programs = await getAllPrograms();

      final workingDays = (config['working_days_per_week'] as int?) ?? 5;

      final periodsPerDay = (config['periods_per_day'] as int?) ?? 6;

      final dayNames = _buildDayNames(workingDays);

      final timetable = <String, dynamic>{};

      for (final program in programs) {
        final programId = (program['id'] ?? '').toString();

        if (programId.isEmpty) {
          continue;
        }

        final dayGrid = <String, List<dynamic>>{};

        for (final day in dayNames) {
          dayGrid[day] = List<dynamic>.filled(periodsPerDay, null);
        }

        timetable[programId] = dayGrid;
      }

      _logEmptyGrid(timetable, dayNames, periodsPerDay);

      return timetable;
    } catch (e, st) {
      dev.log('createEmptyTimetableGrid failed', error: e, stackTrace: st);

      return {};
    }
  }
  Future<Map<String, dynamic>> scheduleLabs(
    Map<String, dynamic> timetable,
    Map<String, dynamic> timetableData,
  ) async {
    try {
      final programsData =
          (timetableData['programs'] as Map<String, dynamic>?) ?? {};

      final orderedDays =
          (timetableData['orderedDayNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          _buildDayNames(5);

      final roomById = _castRoomById(timetableData['roomById']);

      final facultySchedule = <String, Map<String, Set<int>>>{};

      final roomSchedule = <String, Map<String, Set<int>>>{};

      for (final programEntry in programsData.entries) {
        final programId = programEntry.key;

        final programInfo =
            (programEntry.value as Map<String, dynamic>?) ??
            <String, dynamic>{};

        final subjects = (programInfo['subjects'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

        final facultyMap =
            (programInfo['facultyMap'] as Map<String, dynamic>? ?? {}).map(
              (key, value) => MapEntry(key, value.toString()),
            );

        final labRoomMap =
            (programInfo['labRoomMap'] as Map<String, dynamic>? ?? {}).map(
              (key, value) => MapEntry(key, value.toString()),
            );

        final labFrequencyMap =
            (programInfo['labFrequencyMap'] as Map<String, dynamic>? ?? {}).map(
              (key, value) => MapEntry(key, (value as num).toInt()),
            );

        final labSubjects = subjects
            .where((subject) => subject['is_lab'] == true)
            .toList(growable: false);

        final programGrid =
            (timetable[programId] as Map<String, dynamic>?) ??
            <String, dynamic>{};

        if (programGrid.isEmpty || labSubjects.isEmpty) {
          continue;
        }

        final programLabLoad = <String, int>{};

        var subjectIndex = 0;

        for (final subject in labSubjects) {
          final subjectId = (subject['id'] ?? '').toString();

          final facultyId = (facultyMap[subjectId] ?? '').toString();

          final mappedLabRoomId = (labRoomMap[subjectId] ?? '').toString();

          if (subjectId.isEmpty ||
              facultyId.isEmpty ||
              mappedLabRoomId.isEmpty) {
            continue;
          }

          final roomDoc = roomById[mappedLabRoomId];

          if (roomDoc == null || !RoomTypeUtils.isLabRoomDoc(roomDoc)) {
            dev.log(
              'Lab $subjectId skipped: invalid or missing lab room in mapping',
              name: 'TimetableService',
            );
            continue;
          }

          final sessionCount = (labFrequencyMap[subjectId] ?? 0).clamp(0, 10);

          if (sessionCount <= 0) {
            dev.log(
              'Lab $subjectId skipped: lab_frequency resolved to 0',
              name: 'TimetableService',
            );
            continue;
          }

          final usedDaysForSubject = <String>{};
          final assignedDays = <String>[];

          var sessionsPlaced = 0;

          for (var session = 0; session < sessionCount; session++) {
            final dayOrder = _labSessionDayTryOrder(
              orderedDays: orderedDays,
              sessionIndex: session,
              sessionCount: sessionCount,
              subjectRotation: subjectIndex,
              usedDaysForSubject: usedDaysForSubject,
              programLabLoad: programLabLoad,
            );

            final placedDay = _tryPlaceOneLabSession(
              programGrid: programGrid,
              dayTryOrder: dayOrder,
              subjectId: subjectId,
              facultyId: facultyId,
              roomId: mappedLabRoomId,
              facultySchedule: facultySchedule,
              roomSchedule: roomSchedule,
              sessionLength: periodsPerLabSession,
            );

            if (placedDay == null) {
              dev.log(
                'Could not place lab session ${session + 1}/$sessionCount for subject $subjectId in program $programId',
                name: 'TimetableService',
              );
              continue;
            }

            usedDaysForSubject.add(placedDay);
            assignedDays.add(placedDay);

            programLabLoad[placedDay] = (programLabLoad[placedDay] ?? 0) + 1;

            sessionsPlaced++;
          }

          dev.log(
            'Lab distribution => program=$programId subject=$subjectId sessions=$sessionCount placed=$sessionsPlaced days=$assignedDays',
            name: 'TimetableService',
          );

          subjectIndex++;
        }
      }

      _logLabSchedulePreview(timetable);

      return timetable;
    } catch (e, st) {
      dev.log('scheduleLabs failed', error: e, stackTrace: st);

      return timetable;
    }
  }

  Future<Map<String, dynamic>> scheduleLabsFromPreparedData() async {
    final timetableData = await prepareTimetableData();

    final emptyGrid = await createEmptyTimetableGrid();

    return scheduleLabs(emptyGrid, timetableData);
  }

  Future<Map<String, dynamic>> scheduleTheorySubjects(
    Map<String, dynamic> timetable,
    Map<String, dynamic> timetableData,
  ) async {
    try {
      final programsData =
          (timetableData['programs'] as Map<String, dynamic>?) ?? {};

      final orderedDays =
          (timetableData['orderedDayNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          _buildDayNames(5);

      final roomById = _castRoomById(timetableData['roomById']);

      final facultySchedule = <String, Map<String, Set<int>>>{};

      final roomSchedule = <String, Map<String, Set<int>>>{};

      _buildOccupiedSchedulesFromTimetable(
        timetable: timetable,
        facultySchedule: facultySchedule,
        roomSchedule: roomSchedule,
      );

      final assignmentStats = <String, Map<String, int>>{};

      final theoryPlacedTracker = <String, Map<String, Set<String>>>{};

      for (final programEntry in programsData.entries) {
        final programId = programEntry.key;

        final programInfo =
            (programEntry.value as Map<String, dynamic>?) ??
            <String, dynamic>{};

        final subjects = (programInfo['subjects'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

        final facultyMap =
            (programInfo['facultyMap'] as Map<String, dynamic>? ?? {}).map(
              (key, value) => MapEntry(key, value.toString()),
            );

        final theoryRoomMap =
            (programInfo['theoryRoomMap'] as Map<String, dynamic>? ?? {}).map(
              (key, value) => MapEntry(key, value.toString()),
            );

        final theoryFrequencyMap =
            (programInfo['theoryFrequencyMap'] as Map<String, dynamic>? ?? {})
                .map((key, value) => MapEntry(key, (value as num).toInt()));

        final programGrid =
            (timetable[programId] as Map<String, dynamic>?) ??
            <String, dynamic>{};

        if (programGrid.isEmpty) {
          continue;
        }

        final seenTheoryIds = <String>{};

        for (final subject in subjects) {
          final subjectId = (subject['id'] ?? '').toString().trim();

          if (subjectId.isEmpty || !seenTheoryIds.add(subjectId)) {
            continue;
          }

          final lecturesTarget = theoryFrequencyMap[subjectId] ?? 0;

          dev.log(
            'Theory frequency => program=$programId subject=$subjectId value=$lecturesTarget',
            name: 'TimetableService',
          );

          if (lecturesTarget <= 0) {
            continue;
          }

          final facultyId = (facultyMap[subjectId] ?? '').toString();

          final mappedTheoryRoomId = (theoryRoomMap[subjectId] ?? '')
              .toString();

          if (facultyId.isEmpty || mappedTheoryRoomId.isEmpty) {
            continue;
          }

          final roomDoc = roomById[mappedTheoryRoomId];

          if (roomDoc == null || !RoomTypeUtils.isClassroomRoomDoc(roomDoc)) {
            dev.log(
              'Theory $subjectId skipped: classroom missing or mapped theory room is not classroom',
              name: 'TimetableService',
            );
            continue;
          }

          var lecturesNeeded = lecturesTarget;
          var lecturesPlaced = 0;

          while (lecturesNeeded > 0) {
            final assigned = _tryPlaceOneTheoryLecture(
              programId: programId,
              programGrid: programGrid,
              orderedDays: orderedDays,
              subjectId: subjectId,
              facultyId: facultyId,
              roomId: mappedTheoryRoomId,
              facultySchedule: facultySchedule,
              roomSchedule: roomSchedule,
              theoryPlacedTracker: theoryPlacedTracker,
              dayRotationOffset: lecturesPlaced,
            );

            if (!assigned) {
              dev.log(
                'Could not place all theory lectures for subject $subjectId in program $programId. Remaining: $lecturesNeeded',
                name: 'TimetableService',
              );
              break;
            }

            lecturesNeeded--;
            lecturesPlaced++;
          }

          assignmentStats.putIfAbsent(programId, () => <String, int>{});

          assignmentStats[programId]![subjectId] =
              lecturesTarget - lecturesNeeded;
        }
      }

      _logTheorySchedulePreview(timetable, assignmentStats);

      return timetable;
    } catch (e, st) {
      dev.log('scheduleTheorySubjects failed', error: e, stackTrace: st);

      return timetable;
    }
  }

  Future<Map<String, dynamic>> generateFullTimetableFromPreparedData({
    bool persistToFirestore = true,
  }) async {
    final basicInfoService = BasicInformationService();

    final basicInfo = await basicInfoService.load();

    if (basicInfo == null) {
      throw Exception(
        'Timetable details not found. Please save Timetable Name and Session first.',
      );
    }

    final timetableName = basicInfo.timetableName.trim();

    final sessionName = basicInfo.academicSession.sessionName.trim();

    if (timetableName.isEmpty) {
      throw Exception('Timetable name is required.');
    }

    if (sessionName.isEmpty) {
      throw Exception('Session name is required.');
    }

    final timetableData = await prepareTimetableData();

    final emptyGrid = await createEmptyTimetableGrid();

    final withLabs = await scheduleLabs(emptyGrid, timetableData);

    final result = await scheduleTheorySubjects(withLabs, timetableData);

    if (persistToFirestore) {
      await persistNestedTimetableToFirestore(
        result,
        timetableName: timetableName,
        sessionName: sessionName,
      );
    }

    return result;
  }
  Future<List<String>> getWorkingDayNames() async {
    final config = await getConfig();

    final n = (config['working_days_per_week'] as int?) ?? 5;

    return _buildDayNames(n);
  }
  Future<void> persistNestedTimetableToFirestore(
    Map<String, dynamic> timetable, {
    required String timetableName,
    required String sessionName,
  }) async {
    if (timetable.isEmpty) {
      throw Exception('No timetable data to save');
    }

    final config = await getConfig();

    final dayOrder = _buildDayNames(
      (config['working_days_per_week'] as int?) ?? 5,
    );

    final rows = <Map<String, dynamic>>[];

    for (final programEntry in timetable.entries) {
      final programId = programEntry.key;

      final dayGrid =
          (programEntry.value as Map<String, dynamic>?) ?? <String, dynamic>{};

      for (final dayName in dayOrder) {
        final dayIndex = dayOrder.indexOf(dayName);

        if (dayIndex < 0) {
          continue;
        }

        final slots = (dayGrid[dayName] as List<dynamic>?) ?? [];

        for (var period = 0; period < slots.length; period++) {
          final raw = slots[period];

          if (raw is! Map<String, dynamic>) {
            continue;
          }

          final subjectId = (raw['subject_id'] ?? '').toString();

          if (subjectId.isEmpty) {
            continue;
          }

          rows.add({
            'program_id': programId,
            'day': dayIndex,
            'period': period,
            'subject_id': subjectId,
            'faculty_id': (raw['faculty_id'] ?? '').toString(),
            'room_id': (raw['room_id'] ?? '').toString(),
            'type': (raw['type'] ?? 'theory').toString(),
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    if (rows.isEmpty) {
      throw Exception('No timetable rows generated (empty grid)');
    }

    await _saveTimetable(
      rows,
      timetableName: timetableName,
      sessionName: sessionName,
    );
  }
  Future<Map<String, dynamic>> prepareTimetableData() async {
    final timetableData = <String, dynamic>{};

    try {
      final programs = await getAllPrograms();

      final mappings = await getMappings();

      final rooms = await getRooms();

      final config = await getConfig();

      final workingDays = (config['working_days_per_week'] as int?) ?? 5;

      final orderedDayNames = _buildDayNames(workingDays);

      final roomById = _roomDocByIdMap(rooms);

      for (final program in programs) {
        final programId = (program['id'] ?? '').toString();

        if (programId.isEmpty) {
          continue;
        }

        final subjects = await getSubjectsByProgram(programId);

        if (subjects.isEmpty) {
          dev.log(
            'Warning: Program $programId has no subjects',
            name: 'TimetableService',
          );
        }

        final facultyMap = <String, String>{};

        final theoryRoomMap = <String, String>{};

        final labRoomMap = <String, String>{};

        final theoryFrequencyMap = <String, int>{};

        final labFrequencyMap = <String, int>{};

        for (final subject in subjects) {
          final subjectId = (subject['id'] ?? '').toString().trim();

          if (subjectId.isEmpty) {
            continue;
          }

          final row = _mappingRowForSubjectProgram(
            mappings: mappings,
            subjectId: subjectId,
            programId: programId,
          );

          if (row == null) {
            dev.log(
              'Skipping subject $subjectId: no mapping for this program',
              name: 'TimetableService',
            );
            continue;
          }

          final facultyId = (row['faculty_id'] ?? '').toString().trim();

          if (facultyId.isEmpty) {
            dev.log(
              'Skipping subject $subjectId: mapping missing faculty',
              name: 'TimetableService',
            );
            continue;
          }

          final isLabCourse = subject['is_lab'] == true;

          final theoryRoomId = (row['theory_room_id'] ?? row['room_id'] ?? '')
              .toString()
              .trim();

          final labRoomId = (row['lab_room_id'] ?? '').toString().trim();

          final theoryFrequency = _normalizedTheoryFrequency(
            rawTheoryFrequency:
                (row['theory_frequency'] as num?)?.toInt() ??
                (row['theoryFrequency'] as num?)?.toInt(),
            isLabCourse: isLabCourse,
            credits: (subject['credits'] as num?)?.toInt() ?? 0,
          );

          final labFrequency = _normalizedLabFrequency(
            rawLabFrequency:
                (row['lab_frequency'] as num?)?.toInt() ??
                (row['labFrequency'] as num?)?.toInt(),
            isLabCourse: isLabCourse,
            credits: (subject['credits'] as num?)?.toInt() ?? 0,
          );

          if (theoryFrequency > 0 && theoryRoomId.isEmpty) {
            dev.log(
              'Skipping subject $subjectId: theory_frequency > 0 but theory room is missing',
              name: 'TimetableService',
            );
            continue;
          }

          if (theoryFrequency > 0) {
            final theoryRoomDoc = roomById[theoryRoomId];

            if (theoryRoomDoc == null ||
                !RoomTypeUtils.isClassroomRoomDoc(theoryRoomDoc)) {
              dev.log(
                'Skipping subject $subjectId: theory room missing or not a classroom',
                name: 'TimetableService',
              );
              continue;
            }
          }

          if (isLabCourse && labFrequency > 0) {
            if (labRoomId.isEmpty) {
              dev.log(
                'Skipping subject $subjectId: lab_frequency > 0 requires lab_room_id in mapping',
                name: 'TimetableService',
              );
              continue;
            }

            final labRoomDoc = roomById[labRoomId];

            if (labRoomDoc == null || !RoomTypeUtils.isLabRoomDoc(labRoomDoc)) {
              dev.log(
                'Skipping subject $subjectId: lab room missing or not a lab room',
                name: 'TimetableService',
              );
              continue;
            }

            labRoomMap[subjectId] = labRoomId;

            labFrequencyMap[subjectId] = labFrequency;
          }

          facultyMap[subjectId] = facultyId;

          if (theoryFrequency > 0) {
            theoryRoomMap[subjectId] = theoryRoomId;
          }

          theoryFrequencyMap[subjectId] = theoryFrequency;

          if (!isLabCourse) {
            labFrequencyMap[subjectId] = 0;
          }

          dev.log(
            'Prepared frequencies => program=$programId subject=$subjectId isLab=$isLabCourse theory=$theoryFrequency lab=${labFrequencyMap[subjectId] ?? 0}',
            name: 'TimetableService',
          );
        }

        timetableData[programId] = {
          'subjects': subjects,
          'facultyMap': facultyMap,
          'theoryRoomMap': theoryRoomMap,
          'labRoomMap': labRoomMap,
          'theoryFrequencyMap': theoryFrequencyMap,
          'labFrequencyMap': labFrequencyMap,
        };
      }

      final prepared = {
        'programs': timetableData,
        'rooms': rooms,
        'roomById': roomById,
        'orderedDayNames': orderedDayNames,
        'config': config,
      };

      _logPreparedData(prepared);

      return prepared;
    } catch (e, st) {
      dev.log('prepareTimetableData failed', error: e, stackTrace: st);

      return {
        'programs': <String, dynamic>{},
        'rooms': <Map<String, dynamic>>[],
        'roomById': <String, Map<String, dynamic>>{},
        'orderedDayNames': _buildDayNames(5),
        'config': await getConfig(),
      };
    }
  }
  Future<void> generateTimetable() async {
    final programs = await _fetchPrograms();

    final subjects = await _fetchSubjects();

    final mappings = await _fetchMappings();

    final rooms = await _fetchRooms();

    final config = await _fetchConfig();

    if (programs.isEmpty || rooms.isEmpty) {
      throw Exception('Missing programs or rooms');
    }

    final facultySchedule = <String, Map<int, Set<int>>>{};

    final roomSchedule = <String, Map<int, Set<int>>>{};

    final rowsToWrite = <Map<String, dynamic>>[];

    final days = config['working_days']!;

    final periods = config['periods']!;

    for (final program in programs) {
      final programId = program.id;

      final programSubjects = subjects
          .where((s) => (s.data()['program_id'] ?? '') == programId)
          .toList();

      if (programSubjects.isEmpty) {
        continue;
      }

      final tasks = _buildTasks(programSubjects);

      final labTasks = tasks.where((t) => t.isLab).toList();

      final theoryTasks = tasks.where((t) => !t.isLab).toList();

      final grid = _createEmptyGrid(days: days, periods: periods);

      for (final task in labTasks) {
        final ok = _placeLab(
          task: task,
          days: days,
          periods: periods,
          grid: grid,
          mappings: mappings,
          rooms: rooms,
          facultySchedule: facultySchedule,
          roomSchedule: roomSchedule,
        );

        if (!ok) {
          throw Exception(
            'Unable to generate timetable (lab placement failed)',
          );
        }
      }

      for (final task in theoryTasks) {
        final ok = _placeTheory(
          task: task,
          days: days,
          periods: periods,
          grid: grid,
          mappings: mappings,
          rooms: rooms,
          facultySchedule: facultySchedule,
          roomSchedule: roomSchedule,
        );

        if (!ok) {
          throw Exception(
            'Unable to generate timetable (theory placement failed)',
          );
        }
      }

      for (var day = 0; day < days; day++) {
        for (var period = 0; period < periods; period++) {
          final slot = grid[day]![period];

          if (slot.subjectId.isEmpty) {
            continue;
          }

          rowsToWrite.add({
            'program_id': programId,
            'day': day,
            'period': period,
            'subject_id': slot.subjectId,
            'faculty_id': slot.facultyId,
            'room_id': slot.roomId,
            'type': slot.type,
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    if (rowsToWrite.isEmpty) {
      throw Exception('No timetable rows generated');
    }

    // Legacy method does not know timetable name/session.
    // The preferred method is
    // generateFullTimetableFromPreparedData().
    throw Exception(
      'Use generateFullTimetableFromPreparedData() to save a timetable with name and session.',
    );
  }

  List<_Task> _buildTasks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> subjects,
  ) {
    final tasks = <_Task>[];

    for (final subject in subjects) {
      final data = subject.data();

      final credits = (data['credits'] as num?)?.toInt() ?? 0;

      final isLab = data['is_lab'] == true;

      final count = credits;

      for (var i = 0; i < count; i++) {
        tasks.add(_Task(subjectId: subject.id, isLab: isLab));
      }
    }

    return tasks;
  }

  Map<int, List<_Slot>> _createEmptyGrid({
    required int days,
    required int periods,
  }) {
    final grid = <int, List<_Slot>>{};

    for (var d = 0; d < days; d++) {
      grid[d] = List.generate(periods, (_) => const _Slot.empty());
    }

    return grid;
  }

  bool _placeLab({
    required _Task task,
    required int days,
    required int periods,
    required Map<int, List<_Slot>> grid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mappings,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> rooms,
    required Map<String, Map<int, Set<int>>> facultySchedule,
    required Map<String, Map<int, Set<int>>> roomSchedule,
  }) {
    final mapping = _findMapping(mappings, task.subjectId);

    if (mapping == null) {
      return false;
    }

    final facultyId = mapping['faculty_id'] as String? ?? '';

    final roomId = rooms.first.id;

    if (facultyId.isEmpty) {
      return false;
    }

    for (var day = 0; day < days; day++) {
      for (var period = 0; period < periods; period++) {
        if (!grid[day]![period].isEmpty) {
          continue;
        }

        if (_isBusy(facultySchedule, facultyId, day, period)) {
          continue;
        }

        if (_isBusy(roomSchedule, roomId, day, period)) {
          continue;
        }

        grid[day]![period] = _Slot(
          subjectId: task.subjectId,
          facultyId: facultyId,
          roomId: roomId,
          type: 'lab',
        );

        _markBusy(facultySchedule, facultyId, day, period);

        _markBusy(roomSchedule, roomId, day, period);

        return true;
      }
    }

    return false;
  }
  bool _placeTheory({
    required _Task task,
    required int days,
    required int periods,
    required Map<int, List<_Slot>> grid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mappings,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> rooms,
    required Map<String, Map<int, Set<int>>> facultySchedule,
    required Map<String, Map<int, Set<int>>> roomSchedule,
  }) {
    final mapping = _findMapping(mappings, task.subjectId);

    if (mapping == null) {
      return false;
    }

    final facultyId = mapping['faculty_id'] as String? ?? '';

    final roomId = rooms.first.id;

    if (facultyId.isEmpty) {
      return false;
    }

    for (var day = 0; day < days; day++) {
      for (var period = 0; period < periods; period++) {
        if (!grid[day]![period].isEmpty) {
          continue;
        }

        if (_isBusy(facultySchedule, facultyId, day, period)) {
          continue;
        }

        if (_isBusy(roomSchedule, roomId, day, period)) {
          continue;
        }

        grid[day]![period] = _Slot(
          subjectId: task.subjectId,
          facultyId: facultyId,
          roomId: roomId,
          type: 'theory',
        );

        _markBusy(facultySchedule, facultyId, day, period);

        _markBusy(roomSchedule, roomId, day, period);

        return true;
      }
    }

    return false;
  }

  // ============================================================
  // MAPPING HELPERS
  // ============================================================

  Map<String, dynamic>? _findMapping(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> mappings,
    String subjectId,
  ) {
    for (final m in mappings) {
      final data = m.data();

      if ((data['subject_id'] ?? '') == subjectId) {
        return data;
      }
    }

    return null;
  }

  bool _isBusy(
    Map<String, Map<int, Set<int>>> schedule,
    String id,
    int day,
    int period,
  ) {
    return schedule[id]?[day]?.contains(period) == true;
  }

  void _markBusy(
    Map<String, Map<int, Set<int>>> schedule,
    String id,
    int day,
    int period,
  ) {
    schedule.putIfAbsent(id, () => <int, Set<int>>{});

    schedule[id]!.putIfAbsent(day, () => <int>{});

    schedule[id]![day]!.add(period);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchPrograms() {
    return _getDocsFromCandidates(_programCollections);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchSubjects() {
    return _getDocsFromCandidates(_subjectCollections);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchMappings() {
    return _getDocsFromCandidates(_mappingCollections);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchRooms() async {
    return _getDocsFromCandidates(_roomCollections);
  }

  Future<Map<String, int>> _fetchConfig() async {
    final config = await getConfig();

    return {
      'working_days': (config['working_days_per_week'] as int?) ?? 5,
      'periods': (config['periods_per_day'] as int?) ?? 6,
    };
  }

  List<String> _buildDayNames(int workingDays) {
    const baseDays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];

    if (workingDays <= 0) {
      return baseDays;
    }

    if (workingDays <= baseDays.length) {
      return baseDays.sublist(0, workingDays);
    }

    final extended = List<String>.from(baseDays);

    const extraDays = ['Saturday', 'Sunday'];

    for (var i = 0; i < workingDays - baseDays.length; i++) {
      extended.add(extraDays[i % extraDays.length]);
    }

    return extended;
  }
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getDocsFromCandidates(List<String> collections) async {
    for (final collection in collections) {
      try {
        final snap = await _db.collection(collection).get();

        if (snap.docs.isNotEmpty) {
          return snap.docs;
        }
      } catch (e, st) {
        dev.log(
          'Collection fetch failed: $collection',
          error: e,
          stackTrace: st,
          name: 'TimetableService',
        );
      }
    }

    return [];
  }
   Map<String, Map<String, dynamic>> _roomDocByIdMap(List<dynamic> rooms) {
    final out = <String, Map<String, dynamic>>{};

    for (final raw in rooms) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }

      final id = (raw['id'] ?? '').toString();

      if (id.isNotEmpty) {
        out[id] = raw;
      }
    }

    return out;
  }

  Map<String, Map<String, dynamic>> _castRoomById(dynamic raw) {
    if (raw is! Map) {
      return {};
    }

    final out = <String, Map<String, dynamic>>{};

    raw.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        out[k.toString()] = v;
      }
    });

    return out;
  }
  Map<String, dynamic>? _mappingRowForSubjectProgram({
    required List<Map<String, dynamic>> mappings,
    required String subjectId,
    required String programId,
  }) {
    Map<String, dynamic>? found;

    for (final m in mappings) {
      if ((m['subject_id'] ?? '').toString() != subjectId) {
        continue;
      }

      if ((m['program_id'] ?? '').toString() != programId) {
        continue;
      }

      found = m;
    }

    return found;
  }
  int _normalizedTheoryFrequency({
    required int? rawTheoryFrequency,
    required bool isLabCourse,
    required int credits,
  }) {
    if (rawTheoryFrequency != null) {
      return rawTheoryFrequency < 0 ? 0 : rawTheoryFrequency;
    }

    if (isLabCourse) {
      return 0;
    }

    return credits < 0 ? 0 : credits;
  }

  int _normalizedLabFrequency({
    required int? rawLabFrequency,
    required bool isLabCourse,
    required int credits,
  }) {
    if (!isLabCourse) {
      return 0;
    }

    if (rawLabFrequency != null) {
      return rawLabFrequency < 0 ? 0 : rawLabFrequency;
    }

    return credits < 0 ? 0 : credits;
  }
  List<int> _evenlySpacedDayIndices({
    required int dayCount,
    required int sessionCount,
    required int subjectRotation,
  }) {
    if (dayCount <= 0 || sessionCount <= 0) {
      return const [];
    }

    if (sessionCount == 1) {
      return [subjectRotation % dayCount];
    }

    return List<int>.generate(sessionCount, (sessionIndex) {
      final raw = (sessionIndex * (dayCount - 1)) / (sessionCount - 1);

      return ((raw.round() + subjectRotation) % dayCount);
    });
  }

  List<String> _labSessionDayTryOrder({
    required List<String> orderedDays,
    required int sessionIndex,
    required int sessionCount,
    required int subjectRotation,
    required Set<String> usedDaysForSubject,
    required Map<String, int> programLabLoad,
  }) {
    if (orderedDays.isEmpty) {
      return const [];
    }

    final preferredIndices = _evenlySpacedDayIndices(
      dayCount: orderedDays.length,
      sessionCount: sessionCount,
      subjectRotation: subjectRotation,
    );

    final preferredDay = sessionIndex < preferredIndices.length
        ? orderedDays[preferredIndices[sessionIndex]]
        : orderedDays[sessionIndex % orderedDays.length];

    final candidates = List<String>.from(orderedDays)
      ..sort((a, b) {
        final aUsed = usedDaysForSubject.contains(a);

        final bUsed = usedDaysForSubject.contains(b);

        if (aUsed != bUsed) {
          return aUsed ? 1 : -1;
        }

        final loadCompare = (programLabLoad[a] ?? 0).compareTo(
          programLabLoad[b] ?? 0,
        );

        if (loadCompare != 0) {
          return loadCompare;
        }

        if (a == preferredDay) {
          return -1;
        }

        if (b == preferredDay) {
          return 1;
        }

        return orderedDays.indexOf(a).compareTo(orderedDays.indexOf(b));
      });

    return candidates;
  }

  List<String> _rotatedDayOrder(List<String> orderedDays, int rotationOffset) {
    if (orderedDays.isEmpty || rotationOffset <= 0) {
      return orderedDays;
    }

    final shift = rotationOffset % orderedDays.length;

    return [...orderedDays.sublist(shift), ...orderedDays.sublist(0, shift)];
  }

  String? _tryPlaceOneLabSession({
    required Map<String, dynamic> programGrid,
    required List<String> dayTryOrder,
    required String subjectId,
    required String facultyId,
    required String roomId,
    required Map<String, Map<String, Set<int>>> facultySchedule,
    required Map<String, Map<String, Set<int>>> roomSchedule,
    required int sessionLength,
  }) {
    if (sessionLength <= 0) {
      return null;
    }

    for (final day in dayTryOrder) {
      final slots = (programGrid[day] as List<dynamic>?) ?? [];

      if (slots.length < sessionLength) {
        continue;
      }

      for (var start = 0; start <= slots.length - sessionLength; start++) {
        if (_subjectHasLabOnDay(slots, subjectId)) {
          break;
        }

        var canPlace = true;

        for (var offset = 0; offset < sessionLength; offset++) {
          final period = start + offset;

          if (slots[period] != null ||
              _isConflict(facultySchedule, facultyId, day, period) ||
              _isConflict(roomSchedule, roomId, day, period)) {
            canPlace = false;
            break;
          }
        }

        if (!canPlace) {
          continue;
        }

        final labSlot = {
          'subject_id': subjectId,
          'faculty_id': facultyId,
          'room_id': roomId,
          'type': 'lab',
        };

        for (var offset = 0; offset < sessionLength; offset++) {
          final period = start + offset;

          slots[period] = Map<String, dynamic>.from(labSlot);

          _markStringSchedule(facultySchedule, facultyId, day, period);

          _markStringSchedule(roomSchedule, roomId, day, period);
        }

        return day;
      }
    }

    return null;
  }

  bool _isConflict(
    Map<String, Map<String, Set<int>>> schedule,
    String id,
    String day,
    int period,
  ) {
    return schedule[id]?[day]?.contains(period) == true;
  }

  void _markStringSchedule(
    Map<String, Map<String, Set<int>>> schedule,
    String id,
    String day,
    int period,
  ) {
    schedule.putIfAbsent(id, () => <String, Set<int>>{});

    schedule[id]!.putIfAbsent(day, () => <int>{});

    schedule[id]![day]!.add(period);
  }
  void _buildOccupiedSchedulesFromTimetable({
    required Map<String, dynamic> timetable,
    required Map<String, Map<String, Set<int>>> facultySchedule,
    required Map<String, Map<String, Set<int>>> roomSchedule,
  }) {
    for (final programEntry in timetable.entries) {
      final dayGrid =
          (programEntry.value as Map<String, dynamic>?) ?? <String, dynamic>{};

      for (final dayEntry in dayGrid.entries) {
        final day = dayEntry.key;

        final slots = (dayEntry.value as List<dynamic>?) ?? [];

        for (var period = 0; period < slots.length; period++) {
          final slot = slots[period];

          if (slot is! Map<String, dynamic>) {
            continue;
          }

          final facultyId = (slot['faculty_id'] ?? '').toString();

          final roomId = (slot['room_id'] ?? '').toString();

          if (facultyId.isNotEmpty) {
            _markStringSchedule(facultySchedule, facultyId, day, period);
          }

          if (roomId.isNotEmpty) {
            _markStringSchedule(roomSchedule, roomId, day, period);
          }
        }
      }
    }
  }

  bool _tryPlaceOneTheoryLecture({
    required String programId,
    required Map<String, dynamic> programGrid,
    required List<String> orderedDays,
    required String subjectId,
    required String facultyId,
    required String roomId,
    required Map<String, Map<String, Set<int>>> facultySchedule,
    required Map<String, Map<String, Set<int>>> roomSchedule,
    required Map<String, Map<String, Set<String>>> theoryPlacedTracker,
    int dayRotationOffset = 0,
  }) {
    final dayOrder = _rotatedDayOrder(orderedDays, dayRotationOffset);

    for (final day in dayOrder) {
      final slots = (programGrid[day] as List<dynamic>?) ?? [];

      if (_hasTheoryScheduledForDay(
            theoryPlacedTracker,
            programId,
            day,
            subjectId,
          ) ||
          _subjectHasLabOnDay(slots, subjectId) ||
          _subjectAlreadyPlacedInDay(slots, subjectId)) {
        continue;
      }

      for (var period = 0; period < slots.length; period++) {
        if (slots[period] != null) {
          continue;
        }

        if (_isConflict(facultySchedule, facultyId, day, period)) {
          continue;
        }

        if (_isConflict(roomSchedule, roomId, day, period)) {
          continue;
        }

        slots[period] = {
          'subject_id': subjectId,
          'faculty_id': facultyId,
          'room_id': roomId,
          'type': 'theory',
        };

        _markStringSchedule(facultySchedule, facultyId, day, period);

        _markStringSchedule(roomSchedule, roomId, day, period);

        _markTheoryPlaced(theoryPlacedTracker, programId, day, subjectId);

        return true;
      }
    }

    return false;
  }

  bool _hasTheoryScheduledForDay(
    Map<String, Map<String, Set<String>>> tracker,
    String programId,
    String day,
    String subjectId,
  ) {
    final sid = subjectId.trim();

    return tracker[programId]?[day]?.contains(sid) ?? false;
  }

  void _markTheoryPlaced(
    Map<String, Map<String, Set<String>>> tracker,
    String programId,
    String day,
    String subjectId,
  ) {
    final sid = subjectId.trim();

    tracker.putIfAbsent(programId, () => <String, Set<String>>{});

    tracker[programId]!.putIfAbsent(day, () => <String>{});

    tracker[programId]![day]!.add(sid);
  }

  bool _subjectHasLabOnDay(List<dynamic> slots, String subjectId) {
    final target = subjectId.trim();

    for (final slot in slots) {
      if (slot is! Map<String, dynamic>) {
        continue;
      }

      final slotType = (slot['type'] ?? '').toString().toLowerCase();

      if (slotType != 'lab') {
        continue;
      }

      final sid = (slot['subject_id'] ?? '').toString().trim();

      if (sid == target) {
        return true;
      }
    }

    return false;
  }

  bool _subjectAlreadyPlacedInDay(List<dynamic> slots, String subjectId) {
    final target = subjectId.trim();

    for (final slot in slots) {
      if (slot is! Map<String, dynamic>) {
        continue;
      }

      final slotType = (slot['type'] ?? 'theory').toString().toLowerCase();

      if (slotType == 'lab') {
        continue;
      }

      final sid = (slot['subject_id'] ?? '').toString().trim();

      if (sid == target) {
        return true;
      }
    }

    return false;
  }

  void _logPreparedData(Map<String, dynamic> preparedData) {
    final programs = (preparedData['programs'] as Map<String, dynamic>?) ?? {};

    final rooms = (preparedData['rooms'] as List<dynamic>?) ?? [];

    final config = (preparedData['config'] as Map<String, dynamic>?) ?? {};

    dev.log('----- Timetable Data Prepared -----', name: 'TimetableService');

    dev.log('Programs: ${programs.length}', name: 'TimetableService');

    for (final entry in programs.entries) {
      final data = entry.value as Map<String, dynamic>? ?? {};

      final subjects = (data['subjects'] as List<dynamic>?) ?? [];

      final facultyMap = (data['facultyMap'] as Map<String, dynamic>?) ?? {};

      final theoryRoomMap =
          (data['theoryRoomMap'] as Map<String, dynamic>?) ?? {};

      final labRoomMap = (data['labRoomMap'] as Map<String, dynamic>?) ?? {};

      dev.log(
        'Program ${entry.key} -> subjects: ${subjects.length}, maps faculty=${facultyMap.length} theoryR=${theoryRoomMap.length} labR=${labRoomMap.length}',
        name: 'TimetableService',
      );
    }

    dev.log('Rooms: ${rooms.length}', name: 'TimetableService');

    dev.log('Config: $config', name: 'TimetableService');

    dev.log('----------------------------------', name: 'TimetableService');
  }

  void _logEmptyGrid(
    Map<String, dynamic> timetable,
    List<String> days,
    int periodsPerDay,
  ) {
    dev.log('----- Empty Timetable Grid -----', name: 'TimetableService');

    dev.log('Programs: ${timetable.length}', name: 'TimetableService');

    dev.log('Days: ${days.join(', ')}', name: 'TimetableService');

    dev.log('Periods per day: $periodsPerDay', name: 'TimetableService');

    for (final entry in timetable.entries) {
      final dayGrid = entry.value as Map<String, dynamic>? ?? {};

      dev.log('Program ${entry.key}', name: 'TimetableService');

      for (final day in days) {
        final slots = (dayGrid[day] as List<dynamic>?) ?? [];

        dev.log(
          '  $day -> ${slots.length} slots: $slots',
          name: 'TimetableService',
        );
      }
    }

    dev.log('-------------------------------', name: 'TimetableService');
  }

  void _logLabSchedulePreview(Map<String, dynamic> timetable) {
    if (timetable.isEmpty) {
      dev.log(
        'Lab scheduling preview: timetable is empty',
        name: 'TimetableService',
      );
      return;
    }

    final firstProgram = timetable.entries.first;

    final programId = firstProgram.key;

    final programGrid =
        (firstProgram.value as Map<String, dynamic>?) ?? <String, dynamic>{};

    dev.log('----- Lab Scheduling Preview -----', name: 'TimetableService');

    dev.log('Program: $programId', name: 'TimetableService');

    for (final dayEntry in programGrid.entries) {
      final day = dayEntry.key;

      final slots = (dayEntry.value as List<dynamic>?) ?? [];

      dev.log('$day -> $slots', name: 'TimetableService');
    }

    dev.log('-------------------------------', name: 'TimetableService');
  }

  void _logTheorySchedulePreview(
    Map<String, dynamic> timetable,
    Map<String, Map<String, int>> assignmentStats,
  ) {
    if (timetable.isEmpty) {
      dev.log(
        'Theory scheduling preview: timetable is empty',
        name: 'TimetableService',
      );
      return;
    }

    final firstProgram = timetable.entries.first;

    final programId = firstProgram.key;

    final programGrid =
        (firstProgram.value as Map<String, dynamic>?) ?? <String, dynamic>{};

    dev.log('----- Theory Scheduling Preview -----', name: 'TimetableService');

    dev.log('Program: $programId', name: 'TimetableService');

    for (final dayEntry in programGrid.entries) {
      final day = dayEntry.key;

      final slots = (dayEntry.value as List<dynamic>?) ?? [];

      dev.log('$day -> $slots', name: 'TimetableService');
    }

    final stats = assignmentStats[programId] ?? {};

    dev.log('Assigned lectures by subject: $stats', name: 'TimetableService');

    dev.log('-----------------------------------', name: 'TimetableService');
  }

  Future<void> publishTimetable(String timetableId) async {
    if (timetableId.trim().isEmpty) {
      throw Exception('Timetable ID is required');
    }

    final snapshot = await _db
        .collection('timetable')
        .where('timetable_id', isEqualTo: timetableId)
        .where('status', isEqualTo: 'draft')
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('No draft timetable found');
    }

    const chunkSize = 400;

    for (var i = 0; i < snapshot.docs.length; i += chunkSize) {
      final batch = _db.batch();

      final end = (i + chunkSize < snapshot.docs.length)
          ? i + chunkSize
          : snapshot.docs.length;

      for (var j = i; j < end; j++) {
        batch.update(snapshot.docs[j].reference, {
          'status': 'published',
          'published_on': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
    await _db.collection('timetable_config').doc(timetableId).set({
      'status': 'published',
      'published_on': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveTimetable(
    List<Map<String, dynamic>> rows, {
    required String timetableName,
    required String sessionName,
  }) async {
    timetableName = timetableName.trim();

    sessionName = sessionName.trim();

    if (timetableName.isEmpty || sessionName.isEmpty) {
      throw Exception('Timetable name and session name are required.');
    }

    final existingSnapshot = await _db
        .collection('timetable_config')
        .where('document_type', isEqualTo: 'timetable')
        .where('timetable_name', isEqualTo: timetableName)
        .where('session_name', isEqualTo: sessionName)
        .limit(1)
        .get();

    String timetableId;

    if (existingSnapshot.docs.isNotEmpty) {
      final existingDoc = existingSnapshot.docs.first;

      timetableId = existingDoc.id;

      await existingDoc.reference.set({
        'document_type': 'timetable',
        'timetable_name': timetableName,
        'session_name': sessionName,
        'status': 'draft',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      dev.log(
        'Existing timetable found. Reusing timetableId=$timetableId',
        name: 'TimetableService',
      );
    }
    else {
      final newDoc = await _db.collection('timetable_config').add({
        'document_type': 'timetable',
        'timetable_name': timetableName,
        'session_name': sessionName,
        'status': 'draft',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      timetableId = newDoc.id;

      dev.log(
        'New timetable created. timetableId=$timetableId',
        name: 'TimetableService',
      );
    }

    final existingRows = await _db
        .collection('timetable')
        .where('timetable_id', isEqualTo: timetableId)
        .get();

    const chunkSize = 400;

    for (var i = 0; i < existingRows.docs.length; i += chunkSize) {
      final batch = _db.batch();

      final end = (i + chunkSize < existingRows.docs.length)
          ? i + chunkSize
          : existingRows.docs.length;

      for (var j = i; j < end; j++) {
        batch.delete(existingRows.docs[j].reference);
      }

      await batch.commit();
    }

    for (var i = 0; i < rows.length; i += chunkSize) {
      final batch = _db.batch();

      final end = (i + chunkSize < rows.length) ? i + chunkSize : rows.length;

      for (var j = i; j < end; j++) {
        final row = Map<String, dynamic>.from(rows[j]);
        row['timetable_id'] = timetableId;
        row['status'] = 'draft';

        batch.set(_db.collection('timetable').doc(), row);
      }

      await batch.commit();
    }

    dev.log(
      'Timetable saved successfully. ID=$timetableId rows=${rows.length}',
      name: 'TimetableService',
    );
  }
}

class _Task {
  const _Task({required this.subjectId, required this.isLab});

  final String subjectId;
  final bool isLab;
}
class _Slot {
  const _Slot({
    required this.subjectId,
    required this.facultyId,
    required this.roomId,
    this.type = 'theory',
  });

  const _Slot.empty()
    : subjectId = '',
      facultyId = '',
      roomId = '',
      type = 'theory';

  final String subjectId;
  final String facultyId;
  final String roomId;
  final String type;

  bool get isEmpty => subjectId.isEmpty;
}
