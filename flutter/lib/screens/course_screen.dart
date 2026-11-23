import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/course.dart';
import '../services/course_tracker.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../services/ui_prefs.dart';
import '../theme.dart';
import '../widgets/course_map.dart';
import 'settings/common.dart' show errorText, showSnack;

/// Accès aux courses (injectable : les tests passent une version en mémoire).
class CourseOps {
  final Future<List<Course>> Function() load;
  final Future<bool> Function(Course) save; // true envoyée, false en attente
  final Future<void> Function(Course) delete;
  const CourseOps(this.load, this.save, this.delete);

  factory CourseOps.supabase(String userId) => CourseOps(
        () => SupabaseService.instance.getCourses(userId),
        SupabaseService.instance.saveCourse,
        SupabaseService.instance.deleteCourse,
      );
}

/// Onglet Course (version sysiphe-course.apk) : départ avec objectif et pause
/// automatique, suivi GPS en direct sur la carte, résumé, historique.
class CourseScreen extends StatefulWidget {
  final String userId;
  final CourseTracker? tracker;
  final CourseOps? ops;

  const CourseScreen({super.key, required this.userId, this.tracker, this.ops});

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

const _distances = [3000, 5000, 10000, 21097];
const _durees = [20 * 60, 30 * 60, 45 * 60, 60 * 60];

class _CourseScreenState extends State<CourseScreen> {
  late final CourseTracker _t = widget.tracker ?? CourseTracker();
  late final CourseOps _ops = widget.ops ?? CourseOps.supabase(widget.userId);

  GoalType _goalType = GoalType.aucun;
  int _goalDistance = 5000;
  int _goalDuree = 30 * 60;
  bool _autoPause = true;
  List<Course>? _courses;
  Object? _loadError;
  Course? _finished;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_onTrack);
    dataVersion.addListener(_load);
    _restore();
    _load();
  }

  @override
  void dispose() {
    _t.removeListener(_onTrack);
    dataVersion.removeListener(_load);
    if (widget.tracker == null) _t.dispose();
    super.dispose();
  }

  void _onTrack() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final type = await UiPrefs.getString('course_goal_type');
    final d = await UiPrefs.getInt('course_goal_distance');
    final s = await UiPrefs.getInt('course_goal_duree');
    final a = await UiPrefs.getBool('course_auto_pause');
    if (!mounted) return;
    setState(() {
      for (final g in GoalType.values) {
        if (g.name == type) _goalType = g;
      }
      if (d != null && _distances.contains(d)) _goalDistance = d;
      if (s != null && _durees.contains(s)) _goalDuree = s;
      _autoPause = a ?? _autoPause;
    });
  }

  Future<void> _load() async {
    try {
      final c = await _ops.load();
      if (mounted) setState(() => _courses = c);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  CourseGoal get _goal => switch (_goalType) {
        GoalType.aucun => CourseGoal.none,
        GoalType.distance => CourseGoal(GoalType.distance, _goalDistance),
        GoalType.duree => CourseGoal(GoalType.duree, _goalDuree),
      };

  Future<void> _start() async {
    final err = await _t.start(goal: _goal, autoPause: _autoPause);
    if (err != null && mounted) showSnack(context, err);
  }

  void _finish() {
    // Retire l'indication « appui long » encore affichée.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _finished = _t.finish(widget.userId));
  }

  Future<void> _save() async {
    final c = _finished;
    if (c == null) return;
    setState(() => _saving = true);
    try {
      final sent = await _ops.save(c);
      if (!mounted) return;
      showSnack(context,
          sent ? 'Course enregistrée ✓' : 'Enregistrée hors ligne ✓ (envoi automatique)');
      _finished = null;
      _t.reset();
      notifyDataChanged(); // Calendrier, Stats, Records
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette course ?'),
        content: const Text('Elle ne sera pas enregistrée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _finished = null);
    _t.reset();
  }

  @override
  Widget build(BuildContext context) {
    final finished = _finished;
    return Scaffold(
      appBar: AppBar(title: const Text('Course')),
      body: finished != null
          ? _summary(finished)
          : _t.active
              ? _live()
              : _ready(),
    );
  }

  // ─── Avant le départ ─────────────────────────────────────────────────────

  Widget _ready() {
    final theme = Theme.of(context);
    final courses = _courses;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Objectif', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GoalType>(
                    segments: const [
                      ButtonSegment(value: GoalType.aucun, label: Text('Libre')),
                      ButtonSegment(
                          value: GoalType.distance, label: Text('Distance')),
                      ButtonSegment(value: GoalType.duree, label: Text('Durée')),
                    ],
                    selected: {_goalType},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      setState(() => _goalType = s.first);
                      UiPrefs.setString('course_goal_type', s.first.name);
                    },
                  ),
                ),
                if (_goalType != GoalType.aucun) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final v in _goalType == GoalType.distance
                          ? _distances
                          : _durees)
                        ChoiceChip(
                          label: Text(_goalType == GoalType.distance
                              ? (v == 21097 ? 'Semi' : '${v ~/ 1000} km')
                              : '${v ~/ 60} min'),
                          selected: v ==
                              (_goalType == GoalType.distance
                                  ? _goalDistance
                                  : _goalDuree),
                          onSelected: (_) {
                            setState(() {
                              if (_goalType == GoalType.distance) {
                                _goalDistance = v;
                                UiPrefs.setInt('course_goal_distance', v);
                              } else {
                                _goalDuree = v;
                                UiPrefs.setInt('course_goal_duree', v);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pause automatique'),
                  subtitle: const Text('Le chrono s\'arrête quand tu '
                      's\'arrêtes (feu rouge) et repart seul.'),
                  value: _autoPause,
                  onChanged: (v) {
                    setState(() => _autoPause = v);
                    UiPrefs.setBool('course_auto_pause', v);
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    key: const ValueKey('course-start'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepOrange),
                    icon: const Icon(Icons.directions_run),
                    label: const Text('Démarrer',
                        style: TextStyle(fontSize: 18)),
                    onPressed: _start,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                    'Annonce vocale à chaque km (réglage son du chrono). '
                    'Le suivi continue écran éteint.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Mes courses', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (courses == null)
          _loadError != null
              ? Text(errorText(_loadError!))
              : const Center(child: CircularProgressIndicator())
        else if (courses.isEmpty)
          Text('Aucune course pour l\'instant.',
              style: theme.textTheme.bodyMedium)
        else
          for (final c in courses) _CourseTile(c: c, onOpen: () => _open(c)),
      ],
    );
  }

  Future<void> _open(Course c) async {
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => CourseDetailPage(course: c, ops: _ops)));
    if (deleted == true) {
      notifyDataChanged();
      _load();
    }
  }

  // ─── Pendant la course ───────────────────────────────────────────────────

  Widget _live() {
    final t = _t;
    final paused = t.paused;
    final progress = t.goal.progress(t.acc.distance, t.movingSeconds);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Text(formatDuration(t.movingSeconds),
                  key: const ValueKey('course-time'),
                  style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Row(
                children: [
                  _Metric('Distance', formatKm(t.acc.distance),
                      key: const ValueKey('course-distance')),
                  _Metric('Allure', formatPace(t.acc.recentPace())),
                  _Metric('Moyenne', formatPace(t.averagePace)),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: t.goalReached ? Colors.green : Colors.deepOrange,
                  backgroundColor: AppTheme.borderColor,
                ),
                const SizedBox(height: 2),
                Text(t.goalReached
                    ? 'Objectif atteint ✓ (${t.goal.label})'
                    : 'Objectif ${t.goal.label}'),
              ],
              if (paused)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Chip(
                    avatar: const Icon(Icons.pause, size: 18),
                    label: Text(t.state == TrackState.pause
                        ? 'En pause'
                        : 'Pause automatique'),
                  ),
                ),
              if (t.position == null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Recherche du signal GPS…'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CourseMap(
                trace: t.acc.finalTrace(), position: t.position, follow: true),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: t.state == TrackState.pause
                        ? FilledButton.icon(
                            key: const ValueKey('course-resume'),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Reprendre'),
                            onPressed: t.resume,
                          )
                        : FilledButton.tonalIcon(
                            key: const ValueKey('course-pause'),
                            icon: const Icon(Icons.pause),
                            label: const Text('Pause'),
                            onPressed: t.pause,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: Tooltip(
                      message: 'Appui long pour terminer',
                      child: OutlinedButton.icon(
                        key: const ValueKey('course-stop'),
                        icon: const Icon(Icons.stop, color: Colors.red),
                        label: const Text('Terminer\n(appui long)',
                            textAlign: TextAlign.center),
                        onPressed: () => showSnack(
                            context, 'Appui long sur Terminer pour finir'),
                        onLongPress: _finish,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Fin de course ───────────────────────────────────────────────────────

  Widget _summary(Course c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CourseSummary(c: c),
        const SizedBox(height: 12),
        if (c.trace.length >= 2)
          SizedBox(height: 240, child: CourseMap(trace: c.trace)),
        const SizedBox(height: 12),
        _Splits(c: c),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('course-discard'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
                onPressed: _saving ? null : _discard,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('course-save'),
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w600)),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

String _dateLabel(DateTime d) =>
    DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(d);

class _CourseSummary extends StatelessWidget {
  final Course c;
  const _CourseSummary({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dateLabel(c.debut), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              _Metric('Distance', formatKm(c.distanceM.toDouble())),
              _Metric('Durée', formatDuration(c.dureeS)),
              _Metric('Allure', formatPace(c.paceS)),
            ]),
            const SizedBox(height: 8),
            Text(
              [
                if (c.dureeTotaleS - c.dureeS >= 10)
                  'pauses ${formatDuration(c.dureeTotaleS - c.dureeS)}',
                if (c.deniveleM > 0) 'D+ ${c.deniveleM} m',
                if (c.objectif.type != GoalType.aucun)
                  'objectif ${c.objectif.label} '
                      '${c.objectif.reached(c.distanceM.toDouble(), c.dureeS) ? '✓' : '✗'}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Temps de chaque km (et allure, identique pour un km).
class _Splits extends StatelessWidget {
  final Course c;
  const _Splits({required this.c});

  @override
  Widget build(BuildContext context) {
    if (c.splitsS.isEmpty) return const SizedBox.shrink();
    final best = c.splitsS.reduce((a, b) => a < b ? a : b);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Temps par km', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < c.splitsS.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 56, child: Text('Km ${i + 1}')),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: best / c.splitsS[i],
                      minHeight: 8,
                      color: c.splitsS[i] == best
                          ? Colors.green
                          : Colors.deepOrange,
                      backgroundColor: AppTheme.borderColor,
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(formatPace(c.splitsS[i].toDouble()),
                        textAlign: TextAlign.right),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  final Course c;
  final VoidCallback onOpen;
  const _CourseTile({required this.c, required this.onOpen});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.directions_run, color: Colors.deepOrange),
          title: Text(
              '${formatKm(c.distanceM.toDouble())} · ${formatDuration(c.dureeS)}'),
          subtitle: Text(
              '${DateFormat('d MMM yyyy', 'fr_FR').format(c.debut)} · '
              '${formatPace(c.paceS)} /km'),
          trailing: c.pending
              ? const Tooltip(
                  message: 'En attente d\'envoi',
                  child: Icon(Icons.cloud_upload_outlined,
                      key: ValueKey('course-pending'),
                      color: AppTheme.textSecondary))
              : const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      );
}

/// Détail d'une course enregistrée : carte, résumé, temps par km.
class CourseDetailPage extends StatelessWidget {
  final Course course;
  final CourseOps ops;
  const CourseDetailPage({super.key, required this.course, required this.ops});

  @override
  Widget build(BuildContext context) {
    final c = course;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Course'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Supprimer cette course ?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Supprimer')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              try {
                await ops.delete(c);
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(e));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.trace.length >= 2)
            SizedBox(height: 280, child: CourseMap(trace: c.trace)),
          const SizedBox(height: 12),
          _CourseSummary(c: c),
          const SizedBox(height: 12),
          _Splits(c: c),
        ],
      ),
    );
  }
}
