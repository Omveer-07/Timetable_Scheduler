import 'package:flutter/material.dart';
import 'package:timetable_scheduler/routes/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timetable_scheduler/services/timetable_service.dart';

/// Hub for managing timetables. "+ New Timetable" opens [OverviewScreen] for configuration and generation.
class MyTimetablesScreen extends StatefulWidget {
  const MyTimetablesScreen({super.key});

  @override
  State<MyTimetablesScreen> createState() => _MyTimetablesScreenState();
}

class _MyTimetablesScreenState extends State<MyTimetablesScreen> {
  static const _instituteName = 'Tech Institute';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TimetableService _timetableService = TimetableService();

  bool _isLoading = true;

  int _total = 0;
  int _published = 0;
  int _drafts = 0;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _draftTimetables = [];

  @override
  void initState() {
    super.initState();
    _loadTimetables();
  }

  Future<void> _loadTimetables() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final timetableSnapshot = await _db
          .collection('timetable_config')
          .where('document_type', isEqualTo: 'timetable')
          .get();

      final allTimetables = timetableSnapshot.docs;
      final draftDocs = allTimetables.where((doc) {
        final data = doc.data();
        return data['status'] == 'draft';
      }).toList();
      final publishedDocs = allTimetables.where((doc) {
        final data = doc.data();
        return data['status'] == 'published';
      }).toList();

      if (!mounted) return;

      setState(() {
        _draftTimetables = draftDocs;

        _total = allTimetables.length;
        _drafts = draftDocs.length;
        _published = publishedDocs.length;

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load timetables: $e')));
    }
  }

  Future<void> _publishTimetable(String timetableId) async {
    try {
      setState(() {
        _isLoading = true;
      });
      await _timetableService.publishTimetable(timetableId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable published successfully')),
      );

      // Refresh dashboard values and draft list.
      await _loadTimetables();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish timetable: $e')),
      );
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'Generated timetable';
    }

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return 'Generated timetable';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Timetables')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manage all your timetables',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.overview);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'New Timetable',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 28),

            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.calendar_month_outlined,
                    label: 'Total',
                    value: _total.toString(),
                    color: scheme.primaryContainer,
                    onSurface: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.publish_outlined,
                    label: 'Published',
                    value: _published.toString(),
                    color: scheme.tertiaryContainer,
                    onSurface: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.edit_note_outlined,
                    label: 'Drafts',
                    value: _drafts.toString(),
                    color: scheme.secondaryContainer,
                    onSurface: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            Text(
              'Drafts',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 12),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_draftTimetables.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No draft timetable available.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Column(
                children: _draftTimetables.map((doc) {
                  final data = doc.data();

                  final timetableId = doc.id;

                  final timetableName = (data['timetable_name'] ?? '')
                      .toString()
                      .trim();

                  final sessionName = (data['session_name'] ?? '')
                      .toString()
                      .trim();

                  final createdAt = data['created_at'];
                  final updatedAt = data['updated_at'];

                  final displayName = timetableName.isEmpty
                      ? 'Current Timetable — $_instituteName'
                      : timetableName;

                  final createdText = createdAt == null
                      ? 'Generated timetable'
                      : _formatDate(createdAt);

                  final updatedText = updatedAt == null
                      ? 'Ready to publish'
                      : _formatDate(updatedAt);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DraftTimetableCard(
                      name: displayName,
                      created: createdAt == null ? createdText : createdText,
                      updated: updatedAt == null ? updatedText : updatedText,
                      isPublished: false,
                      onPublish: () {
                        _publishTimetable(timetableId);
                      },
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onSurface,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, color: onSurface, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftTimetableCard extends StatelessWidget {
  const _DraftTimetableCard({
    required this.name,
    required this.created,
    required this.updated,
    required this.isPublished,
    required this.onPublish,
  });

  final String name;
  final String created;
  final String updated;
  final bool isPublished;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          color: scheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(isPublished ? 'Published' : 'Draft'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename' || value == 'delete') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$value — coming soon')),
                        );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                'Created $created',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),

              Text(
                'Updated $updated',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),

              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onPublish,
                  child: const Text('Publish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
