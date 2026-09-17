import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timetable_scheduler/models/app_user_profile.dart';
import 'package:timetable_scheduler/routes/app_routes.dart';
import 'package:timetable_scheduler/widgets/logout_app_bar_action.dart';

/// Admin home — shown only when [AppUserProfile.role] is `admin` ([AuthGate]).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.profile});

  final AppUserProfile? profile;

  static const _instituteName = 'Tech Institute';

  String _displayName() {
    final name = profile?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = profile?.email;
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'Admin';
  }

  String _greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final greeting = _greetingForNow();
    final userName = _displayName();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: const [LogoutAppBarAction()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, $userName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _instituteName,
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Chip(
              label: const Text('Admin'),
              avatar: Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: scheme.primary,
              ),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            const SizedBox(height: 28),
            Text(
              'Quick actions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _AdminDashboardCards(scheme: scheme),
            const SizedBox(height: 26),
            _PublishedTimetablesSection(scheme: scheme),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardCards extends StatelessWidget {
  const _AdminDashboardCards({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _QuickActionCard(
        title: 'My Timetables',
        subtitle: 'Manage drafts & published',
        icon: Icons.grid_view_rounded,
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () => Navigator.pushNamed(context, AppRoutes.myTimetables),
      ),
      _QuickActionCard(
        title: 'View Calendar',
        subtitle: 'Weekly grid by program',
        icon: Icons.calendar_month_rounded,
        gradient: LinearGradient(
          colors: [
            scheme.tertiary,
            Color.lerp(scheme.tertiary, scheme.secondary, 0.25)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () => Navigator.pushNamed(context, AppRoutes.calendar),
      ),
      _QuickActionCard(
        title: 'Student View',
        subtitle: 'Open student timetable',
        icon: Icons.school_rounded,
        gradient: LinearGradient(
          colors: [
            scheme.secondary,
            Color.lerp(scheme.secondary, scheme.primary, 0.2)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () => Navigator.pushNamed(context, AppRoutes.viewTimetable),
      ),
      _QuickActionCard(
        title: 'Faculty View',
        subtitle: 'Open faculty schedule',
        icon: Icons.badge_outlined,
        gradient: LinearGradient(
          colors: [
            scheme.secondary,
            Color.lerp(scheme.secondary, scheme.tertiary, 0.2)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () => Navigator.pushNamed(context, AppRoutes.facultySchedule),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop
        if (constraints.maxWidth >= 1200) {
          return Wrap(
            spacing: 20,
            runSpacing: 20,
            children: cards
                .map((card) => SizedBox(width: 300, height: 170, child: card))
                .toList(),
          );
        }

        // Tablet
        if (constraints.maxWidth >= 700) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              childAspectRatio: 1.45,
            ),
            itemBuilder: (_, index) => cards[index],
          );
        }

        // Mobile
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (_, index) => cards[index],
        );
      },
    );
  }
}

class _PublishedTimetablesSection extends StatelessWidget {
  const _PublishedTimetablesSection({required this.scheme});

  final ColorScheme scheme;

  String _displayDate(Timestamp? ts) {
    if (ts == null) return 'Unknown';
    final dt = ts.toDate();
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Published Timetables',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('timetable_config')
              .orderBy('updated_at', descending: true)
              .limit(8)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return _PublishedEmptyCard(
                scheme: scheme,
                title: 'Unable to load published timetables',
                subtitle: 'Check Firestore data or indexes',
                icon: Icons.error_outline_rounded,
              );
            }

            final docs = (snapshot.data?.docs ?? [])
                .where((doc) {
                  final d = doc.data();
                  return d['is_published'] == true ||
                      d['published'] == true ||
                      d['status'] == 'published';
                })
                .take(3)
                .toList();

            if (docs.isEmpty) {
              return _PublishedEmptyCard(
                scheme: scheme,
                title: 'No published timetable available',
                subtitle: 'Publish from My Timetables to see previews here',
                icon: Icons.event_busy_outlined,
              );
            }

            return Column(
              children: docs.map((doc) {
                final d = doc.data();
                final name =
                    (d['timetable_name'] ?? d['name'] ?? 'Untitled timetable')
                        .toString();
                final program =
                    (d['program_name'] ?? d['program'] ?? 'All programs')
                        .toString();
                final session =
                    (d['session'] ??
                            d['academic_session'] ??
                            d['academic_session_name'] ??
                            'Session not set')
                        .toString();
                final status = (d['status'] ?? 'Published').toString();
                final updated = d['updated_at'] as Timestamp?;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PublishedPreviewCard(
                    name: name,
                    programAndSession: '$program • $session',
                    status: status,
                    updatedLabel: _displayDate(updated),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _PublishedPreviewCard extends StatelessWidget {
  const _PublishedPreviewCard({
    required this.name,
    required this.programAndSession,
    required this.status,
    required this.updatedLabel,
  });

  final String name;
  final String programAndSession;
  final String status;
  final String updatedLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(status),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              programAndSession,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              'Updated: $updatedLabel',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedEmptyCard extends StatelessWidget {
  const _PublishedEmptyCard({
    required this.scheme,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final ColorScheme scheme;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surface,
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
