import 'package:flutter/material.dart';
import 'package:timetable_scheduler/routes/app_routes.dart';
import 'package:timetable_scheduler/services/timetable_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final TimetableService _timetableService = TimetableService();
  bool _isGenerating = false;

  Future<void> _generateTimetable() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      await _timetableService.generateFullTimetableFromPreparedData();

      await FirebaseFirestore.instance
          .collection('timetable_stats')
          .doc('counters')
          .set({
            'draft_count': FieldValue.increment(1),
          }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable generated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate timetable: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Manage Timetable System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              _buildNavCard(
                title: 'Basic Information',
                icon: Icons.info_outline,
                color: primaryColor,
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.basicInformation);
                },
              ),
              const SizedBox(height: 14),
              _buildNavCard(
                title: 'Data Input',
                icon: Icons.storage,
                color: primaryColor,
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.instituteData);
                },
              ),
              const SizedBox(height: 14),
              _buildNavCard(
                title: 'Lecture Configuration',
                icon: Icons.settings,
                color: primaryColor,
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.lectureConfiguration);
                },
              ),
              const SizedBox(height: 14),
              _buildNavCard(
                title: 'Generate Timetable',
                icon: Icons.auto_fix_high,
                color: primaryColor,
                onTap: _isGenerating ? null : _generateTimetable,
                trailing: _isGenerating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
