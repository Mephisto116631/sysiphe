import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/effort_model.dart';
import '../models/perf.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Onglet « Modèle » : la vue d'ensemble de l'ancien tableur. On modifie
/// les coefficients, et la grille d'efforts, le détail du calcul et
/// l'impact sur l'historique se recalculent à chaque frappe. Rien n'est
/// enregistré tant qu'on n'appuie pas sur « Appliquer partout ».
/// Réglages + historique ; injectable pour les tests (sinon Supabase).
typedef ModelLoader = Future<(Map<String, dynamic>, List<Perf>)> Function();

class ModelScreen extends StatefulWidget {
  final String userId;
  final ModelLoader? loader;

  const ModelScreen({super.key, required this.userId, this.loader});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  EffortModel? _saved; // tel qu'enregistré
  EffortModel? _draft; // en cours d'édition
  List<Perf> _history = [];
  bool _loading = true;
  bool _applying = false;
  Object? _error;
  int _formVersion = 0; // force la reconstruction des champs (reset)
  int _fieldsVersion = 0; // valeurs remplacées en bloc (générateur)

  // Grille
  String _gridElastique = 'Aucun';
  String _gridTension = 'N/A';
  double _gridTemps = 10;
  String? _selVariante, _selForme;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final (settings, history) = await (widget.loader ?? _loadRemote)();
      if (!mounted) return;
      final model = EffortModel.fromSettings(settings);
      setState(() {
        _saved = model;
        _draft = model;
        _history = history;
        _formVersion++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<(Map<String, dynamic>, List<Perf>)> _loadRemote() async {
    final svc = SupabaseService.instance;
    final res = await Future.wait(
        [svc.getSettings(widget.userId), svc.getAllPerfs(widget.userId)]);
    return (res[0] as Map<String, dynamic>, res[1] as List<Perf>);
  }

  bool get _dirty {
    final a = _saved, b = _draft;
    if (a == null || b == null) return false;
    bool same(Map<String, double> x, Map<String, double> y) =>
        x.length == y.length && x.entries.every((e) => y[e.key] == e.value);
    return a.weight != b.weight ||
        !same(a.variantes, b.variantes) ||
        !same(a.formes, b.formes) ||
        !same(a.elastiques, b.elastiques) ||
        !same(a.tensions, b.tensions);
  }

  /// Toucher à l'algo recalcule tout l'historique de planche : on demande
  /// toujours une confirmation explicite.
  Future<bool> _confirmApply() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Modifier l\'algo d\'effort ?'),
          content: const Text(
              'Le modèle sera enregistré et toutes tes séries de planche '
              'seront recalculées. Cette action change tes efforts, records '
              'et statistiques.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Appliquer')),
          ],
        ),
      ) ??
      false;

  Future<void> _apply() async {
    if (!await _confirmApply() || !mounted) return;
    final m = _draft!;
    setState(() => _applying = true);
    try {
      final svc = SupabaseService.instance;
      await svc.saveSettings(widget.userId, m.toSettings());
      final n = await svc.recalculateEfforts(
        widget.userId,
        weight: m.weight,
        variantes: m.variantes,
        formes: m.formes,
        elastiques: m.elastiques,
        tensions: m.tensions,
      );
      notifyDataChanged(); // Saisie, Stats, Records, Calendrier se rechargent
      if (!mounted) return;
      setState(() => _applying = false);
      await _load();
      _snack('Modèle appliqué · $n séries de planche recalculées');
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      _snack('Erreur : $e', error: true);
    }
  }

  void _reset(EffortModel m) => setState(() {
        _draft = m;
        _formVersion++;
      });

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final m = _draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèle d\'effort'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'saved' && _saved != null) _reset(_saved!);
              if (v == 'defaults' && m != null) {
                _reset(EffortModel.defaults(weight: m.weight));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'saved', child: Text('Annuler les modifications')),
              PopupMenuItem(value: 'defaults', child: Text('Coefficients par défaut')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : _buildBody(context, m!),
      bottomNavigationBar: _loading || _error != null || !_dirty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: _applying ? null : _apply,
                  icon: _applying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.done_all),
                  label: Text(
                      'Appliquer partout (${impactOn(_history, m!).changed} séries changent)'),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, EffortModel m) {
    final theme = Theme.of(context);
    return ListView(
      key: ValueKey(_formVersion),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        // Emplacement TOUJOURS présent : insérer le bandeau en tête décalait
        // les blocs suivants, la carte des coefficients était reconstruite,
        // la section ouverte se repliait et le clavier se fermait.
        if (!_dirty)
          const SizedBox.shrink(key: ValueKey('banner'))
        else
          Container(
            key: const ValueKey('banner'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
                'Brouillon : rien n\'est enregistré tant que tu n\'appuies pas sur '
                '« Appliquer partout ».'),
          ),
        _CoefficientsCard(
          key: const ValueKey('coefficients'),
          model: m,
          fieldsVersion: _fieldsVersion,
          onChanged: (nm) => setState(() => _draft = nm),
          onReplaced: (nm) => setState(() {
            _draft = nm;
            _fieldsVersion++; // les champs reprennent les nouvelles valeurs
          }),
        ),
        const SizedBox(height: 12),
        _gridCard(theme, m),
        const SizedBox(height: 12),
        if (_selVariante != null && _selForme != null) ...[
          _breakdownCard(theme, m),
          const SizedBox(height: 12),
        ],
        _impactCard(theme, m),
      ],
    );
  }

  // ── Grille variante × forme ───────────────────────────────────────────────

  Widget _gridCard(ThemeData theme, EffortModel m) {
    final variantes = m.variantes.keys.toList()
      ..sort((a, b) => m.variantes[a]!.compareTo(m.variantes[b]!));
    final formes = m.formes.keys.toList()
      ..sort((a, b) => m.formes[a]!.compareTo(m.formes[b]!));
    if (!m.elastiques.containsKey(_gridElastique)) _gridElastique = 'Aucun';
    if (!m.tensions.containsKey(_gridTension)) _gridTension = 'N/A';
    int cell(String v, String f) =>
        m.effort(v, f, _gridElastique, _gridTension, _gridTemps);
    var max = 1;
    for (final v in variantes) {
      for (final f in formes) {
        final e = cell(v, f);
        if (e > max) max = e;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grille des efforts', style: theme.textTheme.titleMedium),
            Text('Effort pour un maintien de ${_n(_gridTemps)} s — touche une case '
                'pour voir le détail du calcul.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Dropdown(
                    label: 'Élastique',
                    value: _gridElastique,
                    items: m.elastiques.keys.toList(),
                    onChanged: (v) => setState(() {
                      _gridElastique = v;
                      if (v == 'Aucun') _gridTension = 'N/A';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Dropdown(
                    label: 'Tension',
                    value: _gridTension,
                    items: m.tensions.keys.toList(),
                    onChanged: (v) => setState(() => _gridTension = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: _NumField(
                    label: 'Temps (s)',
                    initial: _gridTemps,
                    onChanged: (v) => setState(() => _gridTemps = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(color: AppTheme.borderColor, width: 0.5),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                    children: [
                      _th('Variante \\ Forme'),
                      for (final f in formes) _th('$f\n${_n(m.formes[f]!)}'),
                    ],
                  ),
                  for (final v in variantes)
                    TableRow(children: [
                      _th('$v · ${_n(m.variantes[v]!)}', left: true),
                      for (final f in formes) _cell(v, f, cell(v, f), max),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String t, {bool left = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(t,
            textAlign: left ? TextAlign.left : TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _cell(String v, String f, int effort, int max) {
    final selected = v == _selVariante && f == _selForme;
    final color = _intensity(effort / max);
    return InkWell(
      onTap: () => setState(() {
        _selVariante = v;
        _selForme = f;
      }),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: selected ? color.withOpacity(0.45) : color.withOpacity(0.18),
        child: Text('$effort',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
      ),
    );
  }

  // ── Détail du calcul ──────────────────────────────────────────────────────

  Widget _breakdownCard(ThemeData theme, EffortModel m) {
    final b = m.breakdown(
        _selVariante!, _selForme!, _gridElastique, _gridTension, _gridTemps);
    Widget row(String label, String formula, String value, {bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
                    Text(formula, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                      color: bold ? AppTheme.primaryBlue : null)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Détail : $_selVariante · $_selForme',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            row('Poids effectif',
                '${_n(m.weight)} kg − ${_n(b.forceElastique)} kg × ${_n(b.ratioTension)}',
                '${b.poidsEffectif.toStringAsFixed(1)} kg'),
            row('Facteur de poids', '(poids effectif / 100)²',
                b.facteurPoids.toStringAsFixed(3)),
            row('Facteur de difficulté',
                '(${_n(b.scoreVariante)} × ${_n(b.scoreForme)})^1,2',
                b.facteurDifficulte.toStringAsFixed(1)),
            const Divider(),
            row('Effort', '${_n(_gridTemps)} s × poids × difficulté / 100',
                '${b.effort} pts',
                bold: true),
          ],
        ),
      ),
    );
  }

  // ── Impact sur l'historique ───────────────────────────────────────────────

  Widget _impactCard(ThemeData theme, EffortModel m) {
    final i = impactOn(_history, m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Impact sur ton historique', style: theme.textTheme.titleMedium),
            Text(
              i.series == 0
                  ? 'Aucune série de planche enregistrée.'
                  : '${i.series} séries de planche · ${i.changed} changeraient '
                      'avec ces coefficients',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (i.parVariante.isNotEmpty)
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(children: [
                    _th('Meilleur effort', left: true),
                    _th('Actuel'),
                    _th('Nouveau'),
                    _th('Écart'),
                  ]),
                  for (final v in i.parVariante)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text('${v.variante} (${v.series})'),
                      ),
                      _num('${v.bestBefore}'),
                      _num('${v.bestAfter}', bold: true),
                      _num(
                        v.delta == 0 ? '=' : '${v.delta > 0 ? '+' : ''}${v.delta}',
                        color: v.delta > 0
                            ? Colors.green.shade700
                            : v.delta < 0
                                ? Colors.red.shade700
                                : null,
                      ),
                    ]),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _num(String t, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : null, color: color)),
      );
}

/// Valeur complète pour un champ éditable (66,64 et non 66,6) : jusqu'à
/// 4 décimales, zéros inutiles retirés.
String _exact(double v) {
  final s = v.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _n(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(v < 1 ? 2 : 1);

/// Vert → orange → rouge (même échelle que les Records).
Color _intensity(double ratio) {
  final r = ratio.clamp(0.0, 1.0);
  return r < 0.5
      ? Color.lerp(const Color(0xFF22C55E), const Color(0xFFF59E0B), r / 0.5)!
      : Color.lerp(const Color(0xFFF59E0B), const Color(0xFFEF4444), (r - 0.5) / 0.5)!;
}

/// Tous les coefficients, modifiables ; chaque frappe recalcule le reste.
class _CoefficientsCard extends StatelessWidget {
  final EffortModel model;
  final int fieldsVersion;
  final ValueChanged<EffortModel> onChanged;
  final ValueChanged<EffortModel> onReplaced; // valeurs remplacées en bloc

  const _CoefficientsCard({
    super.key,
    required this.model,
    required this.fieldsVersion,
    required this.onChanged,
    required this.onReplaced,
  });

  @override
  Widget build(BuildContext context) {
    final m = model;
    Widget section(String title, String help, Map<String, double> values,
            Map<String, double> defaults, EffortModel Function(Map<String, double>) apply,
            {Widget? header}) =>
        ExpansionTile(
          title: Text(title),
          subtitle: Text(help, style: Theme.of(context).textTheme.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            if (header != null) header,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in values.entries)
                  SizedBox(
                    width: 140,
                    child: _NumField(
                      key: ValueKey('$title-${e.key}-$fieldsVersion'),
                      label: e.key,
                      initial: e.value,
                      helper: defaults.containsKey(e.key)
                          ? 'défaut ${_n(defaults[e.key]!)}'
                          : null,
                      onChanged: (v) =>
                          onChanged(apply({...values, e.key: v})),
                    ),
                  ),
              ],
            ),
          ],
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: const Text('Poids corporel'),
            subtitle: const Text('Utilisé pour toutes les séries'),
            trailing: SizedBox(
              width: 90,
              child: _NumField(
                label: 'kg',
                initial: m.weight,
                onChanged: (v) => onChanged(m.copyWith(weight: v)),
              ),
            ),
          ),
          section('Variantes',
              'Difficulté relative — construite pas à pas à partir de '
                  'Fibonacci (1, 2, 3, 5, 8, 13…)',
              m.variantes, kVariantes,
              (x) => m.copyWith(variantes: x)),
          section('Formes', 'Position des hanches', m.formes, kFormes,
              (x) => m.copyWith(formes: x),
              header: _FormeGenerator(
                key: ValueKey('gen-$fieldsVersion'),
                formes: m.formes,
                onGenerate: (f) => onReplaced(m.copyWith(formes: f)),
              )),
          section('Élastiques', 'Aide en kg (valeur des élastiques du commerce)',
              m.elastiques, kElastiques,
              (x) => m.copyWith(elastiques: x)),
          section('Tensions', 'Part de l\'aide transmise (0–1)', m.tensions,
              kTensions, (x) => m.copyWith(tensions: x)),
        ],
      ),
    );
  }
}

/// Champ numérique qui garde sa saisie (le parent ne réécrit pas le texte à
/// chaque frappe) et ne remonte que les valeurs valides.
class _NumField extends StatefulWidget {
  final String label;
  final double initial;
  final String? helper;
  final ValueChanged<double> onChanged;

  const _NumField(
      {super.key,
      required this.label,
      required this.initial,
      required this.onChanged,
      this.helper});

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c =
      TextEditingController(text: _exact(widget.initial));
  bool _invalid = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        helperText: widget.helper,
        helperStyle: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        errorText: _invalid ? 'Invalide' : null,
      ),
      onChanged: (t) {
        final v = double.tryParse(t.replaceAll(',', '.'));
        setState(() => _invalid = v == null || v < 0);
        if (v != null && v >= 0) widget.onChanged(v);
      },
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _Dropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final i in items)
          DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

/// Générateur des formes : base × multiplicateur^rang (comme l'ancien
/// Excel : 34 × 1,4 → 34 · 47,6 · 66,64 · 93,296), dans l'ordre croissant
/// des formes actuelles.
class _FormeGenerator extends StatefulWidget {
  final Map<String, double> formes;
  final ValueChanged<Map<String, double>> onGenerate;

  const _FormeGenerator({super.key, required this.formes, required this.onGenerate});

  @override
  State<_FormeGenerator> createState() => _FormeGeneratorState();
}

class _FormeGeneratorState extends State<_FormeGenerator> {
  late double _base, _ratio;

  @override
  void initState() {
    super.initState();
    final g = inferGeometric(widget.formes) ?? (34.0, 1.4);
    _base = g.$1;
    _ratio = double.parse(g.$2.toStringAsFixed(4));
  }

  @override
  Widget build(BuildContext context) {
    final keys = ascendingKeys(widget.formes);
    final preview = geometricSeries(keys, _base, _ratio);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Générateur', style: theme.textTheme.titleSmall),
          Text('Chaque forme = base × multiplicateur à la puissance de son rang',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'Base (${keys.first})',
                  initial: _base,
                  onChanged: (v) => setState(() => _base = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  label: 'Multiplicateur',
                  initial: _ratio,
                  onChanged: (v) => setState(() => _ratio = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [for (final k in keys) '$k ${_n(preview[k]!)}'].join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _base > 0 && _ratio > 0
                  ? () => widget.onGenerate(preview)
                  : null,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Générer les formes'),
            ),
          ),
        ],
      ),
    );
  }
}
