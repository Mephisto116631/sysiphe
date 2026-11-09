import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/perf.dart';
import '../models/session.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class SaisieScreen extends StatefulWidget {
  final String userId;

  const SaisieScreen({super.key, required this.userId});

  @override
  State<SaisieScreen> createState() => _SaisieScreenState();
}

class _SaisieScreenState extends State<SaisieScreen> {
  // ── État du formulaire ────────────────────────────────────────────────────
  final _exerciceCtrl = TextEditingController();
  final _chargeCtrl =
      TextEditingController(); // valeur de la série (performance)
  final _lestCtrl = TextEditingController(); // lest externe en kg (charge)
  TextEditingController? _acCtrl; // contrôleur interne de l'Autocomplete
  DateTime _date = DateTime.now();
  int _serie = 1;
  // Catégorie choisie (création d'exercice ou séance précédente), valable
  // tant que l'exercice saisi reste [_categorieExo]. Sinon : déduite de l'unité.
  String? _categorie;
  String? _categorieExo;
  String _variante = 'Full';
  String _forme = 'Normal';
  String _elastique = 'Aucun';
  String _tension = 'N/A';
  String _unite = 'Sec';
  bool _showOptions = false;

  // ── État UI ───────────────────────────────────────────────────────────────
  List<Perf> _todayPerfs = [];
  List<String> _exerciceNames = [];
  // Séance précédente, pour la reprendre exercice par exercice.
  List<ExerciseTemplate> _previous = [];
  DateTime? _previousDate;
  bool _saving = false;
  bool _loadingPerfs = true;
  double _weight = 97.0; // poids par défaut, chargé depuis user_settings
  // Calibration planche de l'utilisateur (null = valeurs par défaut).
  Map<String, double>? _variantesCfg, _formesCfg, _elastiquesCfg, _tensionsCfg;

  final _fb = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadTodayPerfs(),
      _loadPrevious(),
      _loadExerciceNames(),
      _loadWeight(),
    ]);
  }

  Future<void> _loadTodayPerfs() async {
    setState(() => _loadingPerfs = true);
    try {
      final perfs =
          await SupabaseService.instance.getPerfsForDate(widget.userId, _date);
      if (!mounted) return;
      setState(() {
        _todayPerfs = perfs;
        _loadingPerfs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPerfs = false);
      _snack('Chargement des séries impossible : $e', error: true);
    }
  }

  Future<void> _loadPrevious() async {
    try {
      final perfs = await SupabaseService.instance
          .getPreviousSession(widget.userId, _date);
      if (!mounted) return;
      setState(() {
        _previous = templatesFrom(perfs);
        _previousDate = perfs.isEmpty ? null : perfs.first.date;
      });
    } catch (_) {
      // Non bloquant : la carte « Séance précédente » n'apparaît pas.
    }
  }

  int _doneToday(String exercice) =>
      _todayPerfs.where((p) => p.exercice == exercice).length;

  ExerciseTemplate? _templateFor(String exercice) {
    for (final t in _previous) {
      if (t.exercice == exercice) return t;
    }
    return null;
  }

  static String _num(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  /// Pré-remplit le formulaire avec la série suivante de cet exercice, telle
  /// qu'elle a été faite à la séance précédente.
  void _applyTemplate(ExerciseTemplate t) {
    final serie = _doneToday(t.exercice) + 1;
    final model = t.seriesFor(serie);
    _acCtrl?.text = t.exercice; // déclenche _onExerciceChanged
    _exerciceCtrl.text = t.exercice;
    _chargeCtrl.text = _num(model.performance);
    _lestCtrl.text = model.charge > 0 ? _num(model.charge) : '';
    setState(() {
      _serie = serie;
      _categorie = model.categorie;
      _categorieExo = t.exercice;
      _unite = const ['Sec', 'Reps', 'Kg'].contains(t.unite) ? t.unite : 'Reps';
      if (model.isPlanche) {
        _showOptions = true;
        // Une valeur absente des listes ferait planter le menu déroulant.
        if (kVariantes.containsKey(model.variante)) _variante = model.variante;
        if (kFormes.containsKey(model.forme)) _forme = model.forme;
        if (kElastiques.containsKey(model.elastique)) {
          _elastique = model.elastique;
        }
        _tension = kTensions.containsKey(model.tension) && _elastique != 'Aucun'
            ? model.tension
            : 'N/A';
      }
    });
  }

  Future<void> _loadExerciceNames() async {
    try {
      final names =
          await SupabaseService.instance.getExerciceNames(widget.userId);
      if (mounted) setState(() => _exerciceNames = names);
    } catch (_) {
      // Non bloquant : l'autocomplétion reste simplement vide.
    }
  }

  Future<void> _loadWeight() async {
    final settings = await SupabaseService.instance.getSettings(widget.userId);
    if (mounted) {
      setState(() {
        _weight = (settings['weight'] as num?)?.toDouble() ?? 97.0;
        _variantesCfg = mergeConfig(settings['variantes_config'], kVariantes);
        _formesCfg = mergeConfig(settings['formes_config'], kFormes);
        _elastiquesCfg =
            mergeConfig(settings['elastiques_config'], kElastiques);
        _tensionsCfg = mergeConfig(settings['tensions_config'], kTensions);
      });
    }
  }

  /// Synchronise le nom d'exercice et adapte le formulaire :
  /// « Planche » → options planche ouvertes et unité en secondes.
  void _onExerciceChanged(String text) {
    _exerciceCtrl.text = text;
    final planche = Perf.isPlancheName(text);
    if (planche && (!_showOptions || _unite != 'Sec')) {
      setState(() {
        _showOptions = true;
        _unite = 'Sec';
      });
    }
  }

  void _setDate(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (day == DateTime(_date.year, _date.month, _date.day)) return;
    setState(() => _date = day);
    _loadTodayPerfs();
    _loadPrevious();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  /// Supprime toutes les séries du jour affiché (comme le web), après
  /// confirmation.
  Future<void> _deleteSession() async {
    final label = DateFormat('EEEE d MMMM', 'fr_FR').format(_date);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la séance ?'),
        content: Text('Les ${_todayPerfs.length} séries du $label seront '
            'supprimées définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.deleteSession(widget.userId, _date);
      await _loadTodayPerfs();
      _snack('Séance du $label supprimée');
    } catch (e) {
      _snack('Erreur : $e', error: true);
    }
  }

  /// « Nouvel exercice » : nom, unité et catégorie, puis formulaire prêt.
  Future<void> _newExercice() async {
    final res = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _NewExerciceDialog(existing: _exerciceNames),
    );
    if (res == null) return;
    final (name, unite, categorie) = res;
    _acCtrl?.text = name;
    _exerciceCtrl.text = name;
    _chargeCtrl.clear();
    _lestCtrl.clear();
    setState(() {
      if (!_exerciceNames.contains(name)) {
        _exerciceNames = [..._exerciceNames, name]..sort();
      }
      _unite = unite;
      _categorie = categorie;
      _categorieExo = name;
      _serie = _doneToday(name) + 1;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _date) {
      setState(() => _date = picked);
      _loadTodayPerfs();
      _loadPrevious();
    }
  }

  Future<void> _save() async {
    if (!_fb.currentState!.validate()) return;
    if (_exerciceCtrl.text.trim().isEmpty) {
      _snack('Renseignez un exercice', error: true);
      return;
    }
    // Une ou plusieurs séries : « 12 » ou « 12 10 8 » (comme le web).
    List<double> valeurs;
    try {
      valeurs = parseSeries(_chargeCtrl.text);
    } on FormatException catch (e) {
      _snack(e.message, error: true);
      return;
    }
    if (valeurs.isEmpty || valeurs.any((v) => v <= 0)) {
      _snack('Valeur invalide', error: true);
      return;
    }

    final exercice = _exerciceCtrl.text.trim();
    final planche = Perf.isPlancheName(exercice);
    final categorie = _categorie != null && _categorieExo == exercice
        ? _categorie!
        : (_unite == 'Sec' ? 'Force Iso' : 'Musculation');
    final lest = _unite == 'Reps'
        ? (double.tryParse(_lestCtrl.text.replaceAll(',', '.')) ?? 0)
        : 0.0;

    final perfs = [
      for (var i = 0; i < valeurs.length; i++)
        Perf(
          userId: widget.userId,
          date: _date,
          exercice: exercice,
          variante: _variante,
          forme: _forme,
          serie: _serie + i,
          performance: valeurs[i],
          charge: lest,
          unite: _unite,
          categorie: categorie,
          elastique: _elastique,
          tension: _tension,
          effortPondere: planche
              ? calculerEffort(
                  variante: _variante,
                  elastique: _elastique,
                  tension: _tension,
                  forme: _forme,
                  temps: valeurs[i],
                  weight: _weight,
                  variantes: _variantesCfg,
                  formes: _formesCfg,
                  elastiquesMap: _elastiquesCfg,
                  tensions: _tensionsCfg,
                )
              : 0,
        ),
    ];

    setState(() => _saving = true);
    try {
      await SupabaseService.instance.savePerfs(perfs);
      _chargeCtrl.clear();
      setState(() => _saving = false);
      await _loadTodayPerfs();
      // Enchaîner : série suivante du même exercice, pré-remplie si
      // l'exercice figurait à la séance précédente.
      final t = _templateFor(exercice);
      if (t != null) {
        _applyTemplate(t);
      } else if (mounted) {
        setState(() => _serie = _doneToday(exercice) + 1);
      }
      _snack(perfs.length > 1
          ? '${perfs.length} séries enregistrées ✓'
          : 'Enregistré ✓');
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erreur : $e', error: true);
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Cette performance sera supprimée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.deletePerf(id);
      await _loadTodayPerfs();
    } catch (e) {
      _snack('Erreur : $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  int get _todayEffort =>
      _todayPerfs.fold(0, (sum, p) => sum + (p.effortPondere ?? 0));

  @override
  void dispose() {
    _exerciceCtrl.dispose();
    _chargeCtrl.dispose();
    _lestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saisie'),
        actions: [
          if (_todayPerfs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _deleteSession,
              tooltip: 'Supprimer la séance',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodayPerfs,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Résumé du jour ────────────────────────────────────────────
            if (_todayPerfs.isNotEmpty) ...[
              _KpiRow(
                sets: _todayPerfs.length,
                effort: _todayEffort,
              ),
              const SizedBox(height: 16),
            ],

            // ── Séance précédente ─────────────────────────────────────────
            if (_previous.isNotEmpty && _previousDate != null) ...[
              _PreviousSessionCard(
                date: _previousDate!,
                templates: _previous,
                doneToday: _doneToday,
                onPick: _applyTemplate,
              ),
              const SizedBox(height: 16),
            ],

            // ── Formulaire ────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _fb,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date : ◀ jour précédent · sélecteur · jour suivant ▶
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Jour précédent',
                            onPressed: () => _setDate(
                                _date.subtract(const Duration(days: 1))),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _pickDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: AppTheme.borderColor),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today,
                                        size: 18,
                                        color: AppTheme.textSecondary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _isToday
                                            ? "Aujourd'hui"
                                            : DateFormat('EEE d MMM', 'fr_FR')
                                                .format(_date),
                                        style: const TextStyle(fontSize: 15),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_isToday)
                            const IconButton(
                                icon: Icon(Icons.chevron_right),
                                onPressed: null)
                          else
                            IconButton(
                              icon: const Icon(Icons.today),
                              tooltip: "Revenir à aujourd'hui",
                              onPressed: () => _setDate(DateTime.now()),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Exercice + création d'un nouvel exercice
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Autocomplete<String>(
                              optionsBuilder: (val) => _exerciceNames
                                  .where((e) => e
                                      .toLowerCase()
                                      .contains(val.text.toLowerCase()))
                                  .take(6),
                              onSelected: _onExerciceChanged,
                              fieldViewBuilder:
                                  (ctx, ctrl, focusNode, onSubmit) {
                                // Branché une seule fois : avant, chaque rebuild
                                // ajoutait un listener et réécrivait le texte
                                // (curseur qui saute pendant la frappe).
                                if (!identical(_acCtrl, ctrl)) {
                                  _acCtrl = ctrl
                                    ..text = _exerciceCtrl.text
                                    ..addListener(
                                        () => _onExerciceChanged(ctrl.text));
                                }
                                return TextFormField(
                                  controller: ctrl,
                                  focusNode: focusNode,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    labelText: 'Exercice',
                                    hintText: 'ex. Planche, Dips…',
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Requis'
                                          : null,
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: AppTheme.primaryBlue),
                            tooltip: 'Nouvel exercice',
                            onPressed: _newExercice,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Série + Unite + Charge
                      Row(
                        children: [
                          // Série
                          Column(
                            children: [
                              const Text('Série',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _SmallBtn(
                                      icon: Icons.remove,
                                      onTap: () => setState(() {
                                            if (_serie > 1) _serie--;
                                          })),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text('$_serie',
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  _SmallBtn(
                                      icon: Icons.add,
                                      onTap: () => setState(() => _serie++)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),

                          // Unité
                          Expanded(
                            flex: 2,
                            child: _DropdownField<String>(
                              label: 'Unité',
                              value: _unite,
                              items: const ['Sec', 'Reps', 'Kg'],
                              onChanged: (v) =>
                                  setState(() => _unite = v ?? 'Sec'),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Charge
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _chargeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              // Plusieurs séries d'un coup : « 12 10 8 »,
                              // « 12/10/8 » ou « 12+10+8 ».
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.,/+; ]')),
                              ],
                              decoration: InputDecoration(
                                labelText: _unite == 'Sec'
                                    ? 'Temps (s)'
                                    : _unite == 'Reps'
                                        ? 'Répétitions'
                                        : 'Poids (kg)',
                                hintText: 'ex. 12 10 8',
                                helperText: 'Plusieurs séries : 12/10/8',
                                helperStyle: const TextStyle(fontSize: 10),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Requis';
                                }
                                try {
                                  return parseSeries(v).isEmpty
                                      ? 'Requis'
                                      : null;
                                } on FormatException {
                                  return 'Invalide';
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Lest (tractions / dips lestés) — conservé d'une
                      // série à l'autre, vide = sans lest.
                      if (_unite == 'Reps') ...[
                        TextFormField(
                          controller: _lestCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.,]')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Lest (kg) — optionnel',
                            hintText: '0',
                            prefixIcon: Icon(Icons.fitness_center, size: 18),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final x = double.tryParse(v.replaceAll(',', '.'));
                            return (x == null || x < 0) ? 'Invalide' : null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Options planche (repliables)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showOptions = !_showOptions),
                        child: Row(
                          children: [
                            Text(
                              'Options planche',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: AppTheme.primaryBlue,
                                      fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _showOptions
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: AppTheme.primaryBlue,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      if (_showOptions) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField<String>(
                                label: 'Variante',
                                value: _variante,
                                items: kVariantes.keys.toList(),
                                onChanged: (v) =>
                                    setState(() => _variante = v ?? 'Full'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField<String>(
                                label: 'Forme',
                                value: _forme,
                                items: kFormes.keys.toList(),
                                onChanged: (v) =>
                                    setState(() => _forme = v ?? 'Normal'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField<String>(
                                label: 'Élastique',
                                value: _elastique,
                                items: kElastiques.keys.toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _elastique = v ?? 'Aucun';
                                    if (_elastique == 'Aucun') _tension = 'N/A';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField<String>(
                                label: 'Tension',
                                value: _tension,
                                items: kTensions.keys.toList(),
                                onChanged: _elastique == 'Aucun'
                                    ? null
                                    : (v) =>
                                        setState(() => _tension = v ?? 'N/A'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Bouton Enregistrer
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label:
                            Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Perfs du jour ─────────────────────────────────────────────
            Text(
              DateFormat('d MMMM', 'fr_FR').format(_date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (_loadingPerfs)
              const Center(child: CircularProgressIndicator())
            else if (_todayPerfs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Aucune saisie pour ce jour',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _todayPerfs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final p = _todayPerfs[i];
                  return _PerfTile(perf: p, onDelete: () => _delete(p.id!));
                },
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─── Composants ───────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int sets;
  final int effort;

  const _KpiRow({required this.sets, required this.effort});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Kpi(label: 'Séries aujourd\'hui', value: '$sets')),
        const SizedBox(width: 10),
        Expanded(
            child: _Kpi(
                label: 'Effort total',
                value: effort > 0 ? '$effort pts' : '—')),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;

  const _Kpi({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _PerfTile extends StatelessWidget {
  final Perf perf;
  final VoidCallback onDelete;

  const _PerfTile({required this.perf, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
          child: Text('S${perf.serie}',
              style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(perf.exercice,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${perf.displayValue}'
          '${perf.isPlanche ? " · ${perf.variante} · ${perf.forme}" : ""}'
          '${(perf.effortPondere ?? 0) > 0 ? " · ${perf.effortPondere} pts" : ""}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
          onPressed: perf.id != null ? onDelete : null,
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SmallBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.bgGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Icon(icon, size: 16, color: AppTheme.textPrimary),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child:
                    Text(item.toString(), style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
    );
  }
}

/// Exercices de la séance précédente : un appui pré-remplit le formulaire
/// avec la série suivante, telle qu'elle a été faite la dernière fois.
class _PreviousSessionCard extends StatelessWidget {
  final DateTime date;
  final List<ExerciseTemplate> templates;
  final int Function(String exercice) doneToday;
  final void Function(ExerciseTemplate) onPick;

  const _PreviousSessionCard({
    required this.date,
    required this.templates,
    required this.doneToday,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history,
                    size: 20, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Séance précédente · '
                    '${DateFormat('EEEE d MMMM', 'fr_FR').format(date)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Touchez un exercice pour le refaire.',
                style: theme.textTheme.bodySmall),
            for (final t in templates)
              _templateTile(context, t, doneToday(t.exercice)),
          ],
        ),
      ),
    );
  }

  Widget _templateTile(BuildContext context, ExerciseTemplate t, int done) {
    final total = t.series.length;
    final finished = done >= total;
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 8),
      dense: true,
      title: Text(t.exercice,
          style: TextStyle(
              decoration: finished ? TextDecoration.lineThrough : null)),
      subtitle: Text(t.summary),
      trailing: finished
          ? const Icon(Icons.check_circle, color: Colors.green)
          : done > 0
              ? Text('$done/$total',
                  style: const TextStyle(
                      color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))
              : const Icon(Icons.play_circle_outline,
                  color: AppTheme.primaryBlue),
      onTap: () => onPick(t),
    );
  }
}

/// « Nouvel exercice » : renvoie (nom, unité, catégorie).
class _NewExerciceDialog extends StatefulWidget {
  final List<String> existing;

  const _NewExerciceDialog({required this.existing});

  @override
  State<_NewExerciceDialog> createState() => _NewExerciceDialogState();
}

class _NewExerciceDialogState extends State<_NewExerciceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cat = TextEditingController(text: 'Musculation');
  String _unite = 'Reps';

  @override
  void dispose() {
    _name.dispose();
    _cat.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final cat = _cat.text.trim();
    Navigator.pop(context, (
      _name.text.trim(),
      _unite,
      cat.isEmpty ? (_unite == 'Sec' ? 'Force Iso' : 'Musculation') : cat,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel exercice'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Nom', hintText: 'ex. Tractions lestées'),
                validator: (v) {
                  final n = v?.trim() ?? '';
                  if (n.isEmpty) return 'Requis';
                  final exists = widget.existing
                      .any((e) => e.toLowerCase() == n.toLowerCase());
                  return exists
                      ? 'Existe déjà : choisissez-le dans la liste'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Unité'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Reps', label: Text('Reps')),
                  ButtonSegment(value: 'Sec', label: Text('Secondes')),
                  ButtonSegment(value: 'Kg', label: Text('Kg')),
                ],
                selected: {_unite},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _unite = v.first;
                  // Catégorie par défaut cohérente avec l'unité.
                  if (_cat.text == 'Musculation' || _cat.text == 'Force Iso') {
                    _cat.text = _unite == 'Sec' ? 'Force Iso' : 'Musculation';
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cat,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    hintText: 'Musculation, Force Iso, Gainage…'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Créer')),
      ],
    );
  }
}
