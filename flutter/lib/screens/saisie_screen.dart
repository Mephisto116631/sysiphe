import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/effort_settings.dart';
import '../models/perf.dart';
import '../models/session.dart';
import '../models/stats.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../services/rest_timer.dart';
import '../theme.dart';
import '../widgets/chrono.dart';
import '../widgets/exercise_card.dart';
import '../widgets/rest_bar.dart';
import '../widgets/saisie/form_bits.dart';
import '../widgets/saisie/kpi.dart';
import '../widgets/saisie/date_nav_row.dart';
import '../widgets/saisie/dialogs.dart';
import '../widgets/saisie/new_exercice_dialog.dart';
import '../widgets/saisie/options_fields.dart';
import '../widgets/saisie/recent_chips.dart';
import '../widgets/saisie/perf_tile.dart';
import '../widgets/saisie/previous_session_card.dart';
import 'minuteur_screen.dart';

class SaisieScreen extends StatefulWidget {
  final String userId;

  const SaisieScreen({super.key, required this.userId});

  @override
  State<SaisieScreen> createState() => _SaisieScreenState();
}

class _SaisieScreenState extends State<SaisieScreen>
    with WidgetsBindingObserver {
  // ── État du formulaire ────────────────────────────────────────────────────
  final _exerciceCtrl = TextEditingController();
  final _chargeCtrl =
      TextEditingController(); // valeur de la série (performance)
  final _lestCtrl = TextEditingController(); // lest externe en kg (charge)
  /// Exemples tirés de la dernière fois, en sous-texte (jamais saisis) :
  /// la série N de l'exercice affiche la série N de la dernière séance.
  /// Suit le sélecteur de série (− / +).
  Perf? get _exemple {
    final ex = _exerciceCtrl.text.trim();
    if (ex.isEmpty) return null;
    return _lastFor(ex)?.seriesFor(_serie);
  }

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
  String _ecartement = 'Standard';
  Set<String> _assistables = {}; // exercices assistables (user_settings)
  String _unite = 'Sec';
  bool _showOptions = false;

  // ── État UI ───────────────────────────────────────────────────────────────
  List<Perf> _todayPerfs = [];
  List<String> _exerciceNames = [];
  Map<String, (String, String)> _exerciceMeta =
      {}; // tout l'historique : unité, catégorie
  // Tout l'historique : panneau du jour, indicateurs par exercice, records.
  List<Perf> _history = [];
  int _nbDaysAvg = 5; // user_settings.nb_days_avg
  bool _enableCharges = true; // user_settings.enable_charges
  // Séance précédente, pour la reprendre exercice par exercice.
  List<ExerciseTemplate> _previous = [];
  DateTime? _previousDate;
  bool _saving = false;
  bool _loadingPerfs = true;
  // Poids et calibrations (planche, assistables) de user_settings.
  EffortSettings _cfg = const EffortSettings();

  final _fb = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_onDataChanged);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadTodayPerfs(),
      _loadPrevious(),
      _loadExerciceNames(),
      _loadWeight(),
      _loadHistory(),
      _rest.load(),
    ]);
    _preselectFirst();
  }

  /// À l'ouverture, la carte principale propose le premier exercice de la
  /// séance précédente (le premier pas encore fait aujourd'hui). Jamais de
  /// changement d'exercice automatique ensuite.
  void _preselectFirst() {
    if (!mounted || _exerciceCtrl.text.trim().isNotEmpty || _previous.isEmpty) {
      return;
    }
    _applyTemplate(nextPending(_previous, _doneToday) ?? _previous.first);
  }

  // ── Repos entre les séries ────────────────────────────────────────────────
  final _rest = RestTimer();

  /// Lance le repos après une série enregistrée (aujourd'hui seulement).
  void _startRest() {
    if (_isToday && mounted) _rest.start();
  }

  // Écran éteint ou autre appli : notification de fin de repos.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _rest.onLifecycle(state);

  /// Exercices du plus récent au plus ancien (liste « Récents »,
  /// autocomplétion) ; ordre alphabétique tant que l'historique charge.
  // ── Petites cartes d'exercices (sous la carte principale) ──────────────
  final List<String> _addedCards = []; // ajoutés à la main pour la séance
  final Map<String, (String, String)> _newCardMeta =
      {}; // nom → (unité, catégorie)

  ExerciseTemplate? _lastFor(String ex) =>
      _templateFor(ex) ?? lastTemplateFor(_history, ex, _date);

  /// Enregistre les séries d'une carte : remplace celles du jour pour cet
  /// exercice (pas de doublon si on réenregistre), comme les blocs du web.
  /// Construit une série (effort pondéré inclus pour planche / assistables).
  Perf _makePerf({
    required String exercice,
    required int serie,
    required double valeur,
    required String unite,
    required String categorie,
    required double lest,
    required String variante,
    required String forme,
    required String elastique,
    required String tension,
    required String ecartement,
  }) {
    final planche = Perf.isPlancheName(exercice);
    final assist = _isAssistable(exercice);
    return Perf(
      userId: widget.userId,
      date: _date,
      exercice: exercice,
      variante: planche ? variante : 'Full',
      forme: planche ? forme : 'Normal',
      serie: serie,
      performance: valeur,
      charge: lest,
      unite: unite,
      categorie: categorie,
      elastique: (planche || assist) ? elastique : 'Aucun',
      tension: (planche || assist) ? tension : 'N/A',
      ecartement: assist ? ecartement : 'N/A',
      effortPondere: assist
          ? _cfg.assiste(
              reps: valeur,
              lest: lest,
              elastique: elastique,
              tension: tension,
              ecartement: ecartement)
          : planche
              ? _cfg.planche(
                  variante: variante,
                  forme: forme,
                  elastique: elastique,
                  tension: tension,
                  temps: valeur)
              : 0,
    );
  }

  /// Enregistre une série saisie dans une carte d'exercice.
  Future<bool> _saveEntry(String ex, CardEntry e) async {
    final last = _lastFor(ex)?.series.first;
    final meta = _newCardMeta[ex];
    final categorie = last?.categorie ??
        meta?.$2 ??
        _exerciceMeta[ex]?.$2 ??
        (e.unite == 'Sec' ? 'Force Iso' : 'Musculation');
    final ins = _usesPoints(ex) ? null : _insight(ex);
    final newPr = ins != null && ins.prSerie > 0 && e.value > ins.prSerie;
    try {
      await SupabaseService.instance.savePerfs([
        _makePerf(
          exercice: ex,
          serie: e.serie,
          valeur: e.value,
          unite: e.unite,
          categorie: categorie,
          lest: e.lest,
          variante: e.variante,
          forme: e.forme,
          elastique: e.elastique,
          tension: e.tension,
          ecartement: e.ecartement,
        ),
      ]);
      await _loadTodayPerfs();
      _loadHistory();
      _snack(newPr
          ? '🏆 $ex : nouveau record en série (${_num(e.value)})'
          : '$ex · série ${e.serie} enregistrée ✓');
      _startRest();
      return true;
    } catch (err) {
      _snack('Erreur : $err', error: true);
      return false;
    }
  }

  /// « + Ajouter un exercice » : exercices récents, ou nouveau.
  Future<void> _addCard(List<String> already) async {
    // Tous les exercices connus (récents d'abord), pas seulement les 90 derniers
    // jours : sinon un ancien exercice semblait « inexistant » sans être listé.
    final choices = [
      ..._recentNames,
      ..._exerciceNames.where((e) => !_recentNames.contains(e)),
    ].where((e) => !already.contains(e)).toList();
    final picked = await pickExerciseSheet(context, choices);
    if (picked == null || !mounted) return;
    var name = picked;
    if (name.isEmpty) {
      final res = await showDialog<(String, String, String)>(
        context: context,
        builder: (_) => NewExerciceDialog(existing: _exerciceNames),
      );
      if (res == null) return;
      name = res.$1;
      // Nom déjà connu : on ouvre l'exercice existant, avec son unité d'origine.
      if (!_exerciceNames.contains(name)) _newCardMeta[name] = (res.$2, res.$3);
    }
    setState(() => _addedCards.add(name));
  }

  /// Une carte par exercice (planche comprise). L'exercice ouvert dans la
  /// carte principale n'est pas répété ; les exercices terminés descendent
  /// en bas de la liste, les restants restent en haut (rotation logique).
  List<Widget> _buildCards() {
    final all = cardExercises(_previous, _todayPerfs, _addedCards,
        includePlanche: true);
    final selected = _exerciceCtrl.text.trim();
    bool finished(String ex) {
      final t = _templateFor(ex);
      final d = _doneToday(ex);
      return t != null ? d >= t.series.length : d > 0;
    }

    final shown = all.where((e) => e != selected).toList();
    final names = [
      ...shown.where((e) => !finished(e)),
      ...shown.where(finished),
    ];
    return [
      for (final ex in names)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ExerciseCard(
            key: ValueKey('card-$ex'),
            exercice: ex,
            unite: _lastFor(ex)?.unite ??
                _newCardMeta[ex]?.$1 ??
                _exerciceMeta[ex]?.$1 ??
                (Perf.isPlancheName(ex) ? 'Sec' : 'Reps'),
            kind: Perf.isPlancheName(ex)
                ? CardKind.planche
                : _isAssistable(ex)
                    ? CardKind.assist
                    : CardKind.plain,
            last: _lastFor(ex),
            helper: _cardHelper(ex),
            insight: _cardInsight(ex),
            done: _doneToday(ex),
            enableCharges: _enableCharges,
            variantes: (_cfg.variantes ?? kVariantes).keys.toList(),
            formes: (_cfg.formes ?? kFormes).keys.toList(),
            elastiques: (_cfg.elastiques ?? kElastiques).keys.toList(),
            tensions: (_cfg.tensions ?? kTensions).keys.toList(),
            ecartements: (_cfg.ecartements ?? kEcartements).keys.toList(),
            onSave: (e) => _saveEntry(ex, e),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => _addCard(all),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un exercice'),
      ),
      const SizedBox(height: 20),
    ];
  }

  /// Ligne grise sous le champ : date de la dernière fois et record.
  String? _cardHelper(String ex) {
    final t = _lastFor(ex);
    if (t == null) return 'Nouvel exercice';
    final ins = _insight(ex);
    final date = DateFormat('d MMM', 'fr_FR').format(t.series.first.date);
    return 'Dernière fois le $date'
        '${ins == null ? '' : ' · record série ${_num(ins.prSerie)}'}';
  }

  /// % vs moyenne des dernières séances, à série égale, sur chaque carte.
  Widget? _cardInsight(String ex) {
    final ins = _insight(ex);
    if (ins == null) return null;
    final sets = _todayPerfs.where((p) => p.exercice == ex);
    return InsightLine(
        insight: ins,
        todayVolume: _todayVolume(sets, ex),
        todaySets: sets.length,
        unit: _unitFor(ex),
        nbDaysAvg: _nbDaysAvg);
  }

  List<String> get _recentNames =>
      _history.isNotEmpty ? exercisesByRecency(_history) : _exerciceNames;

  /// Choisir un exercice : reprend ce qui a été fait la dernière fois
  /// (séance précédente, sinon dernière séance où il apparaît).
  Future<void> _pickExercise(String ex) async {
    await _flushPending();
    if (!mounted) return;
    final t = _templateFor(ex) ?? lastTemplateFor(_history, ex, _date);
    if (t != null) {
      _applyTemplate(t);
    } else {
      _acCtrl?.text = ex;
      _onExerciceChanged(ex);
      setState(() => _serie = _doneToday(ex) + 1);
    }
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
    // La dernière séance sert d'exemple (sous-texte), pas de valeur saisie.
    _chargeCtrl.clear();
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
      final meta =
          await SupabaseService.instance.getExerciceMeta(widget.userId);
      if (mounted) {
        setState(() {
          _exerciceMeta = meta;
          _exerciceNames = meta.keys.toList()..sort();
        });
      }
    } catch (_) {
      // Non bloquant : l'autocomplétion reste simplement vide.
    }
  }

  Future<void> _loadHistory() async {
    try {
      final all = await SupabaseService.instance.getAllPerfs(widget.userId);
      if (mounted) setState(() => _history = all);
    } catch (_) {
      // Non bloquant : indicateurs masqués.
    }
  }

  bool _isAssistable(String ex) =>
      !Perf.isPlancheName(ex) && _assistables.contains(ex.trim());

  /// Planche et exercices assistables : indicateurs en points d'effort.
  bool _usesPoints(String ex) => Perf.isPlancheName(ex) || _isAssistable(ex);
  String _unitFor(String ex) => _usesPoints(ex) ? ' pts' : '';

  /// Effort d'une série, non arrondi (recalculé depuis ses paramètres pour
  /// les exercices assistables : l'historique est donc toujours cohérent).
  double _effortValue(Perf p) => Perf.isPlancheName(p.exercice)
      ? (p.effortPondere ?? 0).toDouble()
      : _cfg.assisteExact(p);

  ExerciseInsight? _insight(String exercice) =>
      insightFor(_history.where((p) => p.exercice == exercice).toList(), _date,
          nbDaysAvg: _nbDaysAvg,
          valueOf: _usesPoints(exercice) ? _effortValue : null);

  /// Volume du jour d'un exercice, dans la même unité que [_insight].
  double _todayVolume(Iterable<Perf> sets, String exercice) => sets.fold(0.0,
      (s, p) => s + (_usesPoints(exercice) ? _effortValue(p) : p.performance));

  Future<void> _loadWeight() async {
    final settings = await SupabaseService.instance.getSettings(widget.userId);
    if (mounted) {
      setState(() {
        _cfg = EffortSettings.fromSettings(settings);
        _nbDaysAvg = (settings['nb_days_avg'] as num?)?.toInt() ?? 5;
        _enableCharges = settings['enable_charges'] as bool? ?? true;
        final a = settings['assistable_exercises'];
        _assistables = a is List ? a.map((e) => '$e'.trim()).toSet() : {};
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
    } else if (!planche) {
      // Plus la planche : options masquées et remises à zéro, pour qu'elles
      // ne soient jamais enregistrées avec un autre exercice.
      setState(() {
        _showOptions = false;
        _variante = 'Full';
        _forme = 'Normal';
        if (!_isAssistable(text)) {
          _elastique = 'Aucun';
          _tension = 'N/A';
          _ecartement = 'Standard';
        }
      });
    }
  }

  Future<void> _setDate(DateTime d) async {
    final day = DateTime(d.year, d.month, d.day);
    if (day == DateTime(_date.year, _date.month, _date.day)) return;
    await _flushPending();
    if (!mounted) return;
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
    if (!await confirmDelete(context,
        title: 'Supprimer la séance ?',
        content: 'Les ${_todayPerfs.length} séries du $label seront '
            'supprimées définitivement.')) {
      return;
    }
    try {
      await SupabaseService.instance.deleteSession(widget.userId, _date);
      await _loadTodayPerfs();
      _loadHistory();
      _snack('Séance du $label supprimée');
    } catch (e) {
      _snack('Erreur : $e', error: true);
    }
  }

  /// « Nouvel exercice » : nom, unité et catégorie, puis formulaire prêt.
  Future<void> _newExercice() async {
    final res = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => NewExerciceDialog(existing: _exerciceNames),
    );
    if (res == null) return;
    final (name, unite, categorie) = res;
    if (_exerciceNames.contains(name)) {
      await _pickExercise(name); // existe déjà : on l'ouvre tel quel
      return;
    }
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

  /// Enregistrement automatique : 3 s après la dernière frappe, ou dès
  /// qu'on change d'exercice / de jour.
  Timer? _autoTimer;

  void _scheduleAutoSave(String _) {
    _autoTimer?.cancel();
    if (_chargeCtrl.text.trim().isEmpty) return;
    _autoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_saving) _save();
    });
  }

  /// Enregistre tout de suite une saisie en attente (avant un changement).
  Future<void> _flushPending() async {
    if (_autoTimer?.isActive ?? false) {
      _autoTimer!.cancel();
      if (!_saving && _chargeCtrl.text.trim().isNotEmpty) await _save();
    }
  }

  Future<void> _save() async {
    _autoTimer?.cancel();
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
    final categorie = _categorie != null && _categorieExo == exercice
        ? _categorie!
        : (_unite == 'Sec' ? 'Force Iso' : 'Musculation');
    // Champ lest désactivé dans les Réglages : jamais de lest enregistré
    // (même si la séance reprise en avait un).
    final lest = _unite == 'Reps' && _enableCharges
        ? (double.tryParse(_lestCtrl.text.replaceAll(',', '.')) ?? 0)
        : 0.0;

    final perfs = [
      for (var i = 0; i < valeurs.length; i++)
        _makePerf(
          exercice: exercice,
          serie: _serie + i,
          valeur: valeurs[i],
          unite: _unite,
          categorie: categorie,
          lest: lest,
          variante: _variante,
          forme: _forme,
          elastique: _elastique,
          tension: _tension,
          ecartement: _ecartement,
        ),
    ];

    // Nouveau record en une série ? (hors planche : son record est l'effort)
    final ins = _usesPoints(exercice) ? null : _insight(exercice);
    final best = valeurs.reduce((a, b) => a > b ? a : b);
    final newPr = ins != null && ins.prSerie > 0 && best > ins.prSerie;

    setState(() => _saving = true);
    try {
      await SupabaseService.instance.savePerfs(perfs);
      _chargeCtrl.clear();
      setState(() => _saving = false);
      await _loadTodayPerfs();
      // Série suivante du même exercice, pré-remplie si l'exercice figurait
      // à la séance précédente. Jamais de changement d'exercice automatique.
      final t = _templateFor(exercice);
      if (t != null && _doneToday(exercice) < t.series.length) {
        _applyTemplate(t);
      } else if (mounted) {
        setState(() => _serie = _doneToday(exercice) + 1);
      }
      _loadHistory();
      _snack(newPr
          ? '🏆 Nouveau record en série : ${_num(best)} (ancien : ${_num(ins.prSerie)})'
          : perfs.length > 1
              ? '${perfs.length} séries enregistrées ✓'
              : 'Enregistré ✓');
      _startRest();
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erreur : $e', error: true);
    }
  }

  /// Corrige une série déjà enregistrée (ex. rajouter des reps).
  Future<void> _editPerf(Perf p) async {
    if (p.id == null) return;
    final v = await askPerfValue(context, p);
    if (v == null || v <= 0 || v == p.performance) return;
    try {
      await SupabaseService.instance.updatePerfValue(
        p.id!,
        v,
        effortPondere: _isAssistable(p.exercice)
            ? _cfg.assiste(
                reps: v,
                lest: p.charge,
                elastique: p.elastique,
                tension: p.tension,
                ecartement: p.ecartement)
            : p.isPlanche
                ? _cfg.planche(
                    variante: p.variante,
                    forme: p.forme,
                    elastique: p.elastique,
                    tension: p.tension,
                    temps: v)
                : null,
      );
      await _loadTodayPerfs();
      _loadHistory();
    } catch (e) {
      _snack('Erreur : $e', error: true);
    }
  }

  Future<void> _delete(int id) async {
    if (!await confirmDelete(context,
        title: 'Supprimer ?', content: 'Cette performance sera supprimée.')) {
      return;
    }
    try {
      await SupabaseService.instance.deletePerf(id);
      await _loadTodayPerfs();
      _loadHistory();
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

  void _onDataChanged() {
    if (mounted) {
      _loadWeight();
      _loadHistory();
      _loadTodayPerfs();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _rest.dispose();
    WidgetsBinding.instance.removeObserver(this);
    dataVersion.removeListener(_onDataChanged);
    _exerciceCtrl.dispose();
    _chargeCtrl.dispose();
    _lestCtrl.dispose();
    super.dispose();
  }

  /// Carte de saisie principale (date, exercice, valeur, options).
  Widget _buildForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _fb,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateNavRow(
                date: _date,
                isToday: _isToday,
                onPrevious: () =>
                    _setDate(_date.subtract(const Duration(days: 1))),
                onPick: _pickDate,
                onToday: () => _setDate(DateTime.now()),
              ),
              const SizedBox(height: 12),

              ..._exerciseFields(),
              // Indicateurs de l'exercice (en-tête des blocs du web)
              ListenableBuilder(
                listenable: _exerciceCtrl,
                builder: (context, _) {
                  final ex = _exerciceCtrl.text.trim();
                  if (ex.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final ins = _insight(ex);
                  final todaySets = _todayPerfs.where((p) => p.exercice == ex);
                  final today = _todayVolume(todaySets, ex);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InsightLine(
                        insight: ins,
                        todayVolume: today,
                        todaySets: todaySets.length,
                        unit: _unitFor(ex),
                        nbDaysAvg: _nbDaysAvg),
                  );
                },
              ),

              ..._valueFields(),
              // Bouton Enregistrer
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(
                    _saving ? 'Enregistrement…' : 'Enregistrer maintenant'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Champ exercice (autocomplétion, ⊕ nouvel exercice) et puces « Récents ».
  List<Widget> _exerciseFields() => [
        // Exercice + création d'un nouvel exercice
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Autocomplete<String>(
                // Du plus récent au plus ancien
                optionsBuilder: (val) => _recentNames
                    .where(
                        (e) => e.toLowerCase().contains(val.text.toLowerCase()))
                    .take(8),
                onSelected: _pickExercise,
                fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
                  // Branché une seule fois : avant, chaque rebuild
                  // ajoutait un listener et réécrivait le texte
                  // (curseur qui saute pendant la frappe).
                  if (!identical(_acCtrl, ctrl)) {
                    _acCtrl = ctrl
                      ..text = _exerciceCtrl.text
                      ..addListener(() => _onExerciceChanged(ctrl.text));
                  }
                  return TextFormField(
                    controller: ctrl,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Exercice',
                      hintText: 'ex. Planche, Dips…',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requis' : null,
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

        // Anciens exercices, du plus récent au plus ancien :
        // un appui reprend la dernière fois.
        if (_recentNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _exerciceCtrl,
            builder: (context, _) => RecentChips(
              names: _recentNames.take(15).toList(),
              selected: _exerciceCtrl.text.trim(),
              doneToday: (e) => _doneToday(e) > 0,
              onPick: _pickExercise,
            ),
          ),
        ],
        const SizedBox(height: 12),
      ];

  /// Série, unité, valeur, chrono, lest et options planche / assistable.
  List<Widget> _valueFields() => [
        // Série + Unite + Charge
        Row(
          children: [
            SeriesStepper(
              serie: _serie,
              onChanged: (v) => setState(() => _serie = v),
            ),
            const SizedBox(width: 16),

            // Unité
            Expanded(
              flex: 2,
              child: DropdownField<String>(
                label: 'Unité',
                value: _unite,
                items: const ['Sec', 'Reps', 'Kg'],
                onChanged: (v) => setState(() => _unite = v ?? 'Sec'),
              ),
            ),
            const SizedBox(width: 10),

            // Charge
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _chargeCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Plusieurs séries d'un coup : « 12 10 8 »,
                // « 12/10/8 » ou « 12+10+8 ».
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,/+; ]')),
                ],
                decoration: InputDecoration(
                  labelText: _unite == 'Sec'
                      ? 'Temps (s)'
                      : _unite == 'Reps'
                          ? 'Répétitions'
                          : 'Poids (kg)',
                  hintText: _exemple == null
                      ? 'ex. 12'
                      : 'ex. ${_num(_exemple!.performance)}',
                  helperText: 'Enregistré après 3 s',
                  helperStyle: const TextStyle(fontSize: 10),
                ),
                onChanged: _scheduleAutoSave,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Requis';
                  }
                  try {
                    return parseSeries(v).isEmpty ? 'Requis' : null;
                  } on FormatException {
                    return 'Invalide';
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Chronomètre pour les exercices en secondes
        if (_unite == 'Sec') ...[
          Chrono(
              exercice: _exerciceCtrl.text,
              onStop: (sec) {
                _chargeCtrl.text = '$sec';
                _scheduleAutoSave(_chargeCtrl.text);
              }),
          const SizedBox(height: 12),
        ],

        // Lest (tractions / dips lestés) — conservé d'une
        // série à l'autre, vide = sans lest.
        if (_unite == 'Reps' && _enableCharges) ...[
          TextFormField(
            controller: _lestCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Lest (kg) — optionnel',
              hintText: (_exemple?.charge ?? 0) > 0
                  ? 'ex. ${_num(_exemple!.charge)}'
                  : '0',
              prefixIcon: const Icon(Icons.fitness_center, size: 18),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final x = double.tryParse(v.replaceAll(',', '.'));
              return (x == null || x < 0) ? 'Invalide' : null;
            },
          ),
          const SizedBox(height: 12),
        ],

        // Options planche : uniquement pour la planche
        if (Perf.isPlancheName(_exerciceCtrl.text)) ...[
          PlancheOptions(
            expanded: _showOptions,
            onToggle: () => setState(() => _showOptions = !_showOptions),
            variante: _variante,
            forme: _forme,
            elastique: _elastique,
            tension: _tension,
            variantes: kVariantes.keys.toList(),
            formes: kFormes.keys.toList(),
            elastiques: kElastiques.keys.toList(),
            tensions: kTensions.keys.toList(),
            onVariante: (v) => setState(() => _variante = v),
            onForme: (v) => setState(() => _forme = v),
            onElastique: (v) => setState(() {
              _elastique = v;
              if (v == 'Aucun') _tension = 'N/A';
            }),
            onTension: (v) => setState(() => _tension = v),
          ),
        ],
        // Exercice assistable : élastique, tension, écartement
        if (_isAssistable(_exerciceCtrl.text)) ...[
          const SizedBox(height: 10),
          AssistOptions(
            elastique: _elastique,
            tension: _tension,
            ecartement: _ecartement,
            elastiques: (_cfg.elastiques ?? kElastiques).keys.toList(),
            tensions: (_cfg.tensions ?? kTensions).keys.toList(),
            ecartements: (_cfg.ecartements ?? kEcartements).keys.toList(),
            onElastique: (v) => setState(() => _elastique = v),
            onTension: (v) => setState(() => _tension = v),
            onEcartement: (v) => setState(() => _ecartement = v),
          ),
        ],
        const SizedBox(height: 16),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saisie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MinuteurScreen())),
            tooltip: 'Minuteur (préparation, exercice, repos)',
          ),
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
            // ── Repos entre les séries ────────────────────────────────────
            ListenableBuilder(
              listenable: _rest,
              builder: (_, __) => RestBar(
                seconds: _rest.seconds,
                onConfig: _rest.setSeconds,
                left: _rest.left,
                onSkip: _rest.stop,
                onAdjust: _rest.adjust,
              ),
            ),
            const SizedBox(height: 12),

            // ── Résumé du jour ────────────────────────────────────────────
            if (_history.isNotEmpty || _todayPerfs.isNotEmpty) ...[
              KpiRow(
                sets: _todayPerfs.length,
                effort: _todayEffort,
                monthSessions: sessionsInMonth(_history, _date),
                week: weekVolume(_history, DateTime.now()),
              ),
              const SizedBox(height: 16),
            ],

            // ── Séance précédente ─────────────────────────────────────────
            if (_previous.isNotEmpty && _previousDate != null) ...[
              PreviousSessionCard(
                date: _previousDate!,
                templates: _previous,
                doneToday: _doneToday,
                onPick: _applyTemplate,
              ),
              const SizedBox(height: 16),
            ],

            // ── Formulaire ────────────────────────────────────────────────
            _buildForm(context),
            const SizedBox(height: 16),

            // ── Petites cartes : un exercice chacune, saisie rapide ───────
            ..._buildCards(),

            // ── Perfs du jour ─────────────────────────────────────────────
            DayPerfList(
              date: _date,
              loading: _loadingPerfs,
              perfs: _todayPerfs,
              onEdit: _editPerf,
              onDelete: (p) => _delete(p.id!),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
