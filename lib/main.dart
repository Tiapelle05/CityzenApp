import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ambiente/formato_ambiente.dart';
import 'ambiente/scheda_aria.dart';
import 'ambiente/schermata_ambiente.dart';
import 'ambiente/stato_ambiente.dart';
import 'assistente/schermata_assistente.dart';
import 'citizen_api.dart';
import 'modelli/ambiente.dart';
import 'mappa_parco.dart';
import 'schermata_accesso.dart';
import 'schermata_segnalazioni.dart';
import 'ui.dart';

export 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await CitizenApi.instance.initialize().timeout(const Duration(seconds: 5));
  } catch (_) {
    // L'app resta utilizzabile anche se il backend non è ancora avviato.
  }
  runApp(const ParkApp());
}

class ParkApp extends StatefulWidget {
  const ParkApp({super.key});

  @override
  State<ParkApp> createState() => _ParkAppState();
}

class TreeyesApp extends ParkApp {
  const TreeyesApp({super.key}) : super();
}

/// Come scegliere il tema: segue il sistema oppure è fissato dall'utente.
enum ModoTema { sistema, chiaro, scuro }

class _ParkAppState extends State<ParkApp> with WidgetsBindingObserver {
  static const _chiaveTema = 'tema_app';

  bool _inglese = false;
  /// Falso finché l'utente non ha scelto un server o la demo: si mostra la pagina di accesso.
  bool _collegato = CitizenApi.instance.configurato;
  /// Cresce a ogni nuovo collegamento: tutte le schermate ricaricano i dati.
  int _sessione = 0;
  ModoTema _modoTema = ModoTema.sistema;
  /// Tema già calcolato e per quale luminosità: si rifà solo quando cambia.
  ThemeData? _tema;
  bool? _temaScuro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_leggiTema());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _leggiTema() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvato = ModoTema.values.asNameMap()[prefs.getString(_chiaveTema)];
      if (salvato != null && salvato != _modoTema && mounted) _cambiaTema(salvato, salva: false);
    } catch (_) {
      // Senza preferenze salvate il tema segue il sistema.
    }
  }

  bool get _scuro => switch (_modoTema) {
        ModoTema.chiaro => false,
        ModoTema.scuro => true,
        ModoTema.sistema => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      };

  /// Cambia tema e ricostruisce tutte le schermate senza perderne lo stato.
  void _cambiaTema(ModoTema modo, {bool salva = true}) {
    setState(() => _modoTema = modo);
    ricostruisciTutto(context);
    if (salva) unawaited(_salvaTema(modo));
  }

  Future<void> _salvaTema(ModoTema modo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chiaveTema, modo.name);
    } catch (_) {}
  }

  @override
  void didChangePlatformBrightness() {
    if (_modoTema != ModoTema.sistema) return;
    setState(() {});
    ricostruisciTutto(context);
  }

  @override
  Widget build(BuildContext context) {
    void cambiaLingua(bool valore) => setState(() => _inglese = valore);
    final scuro = _scuro;
    if (_tema == null || _temaScuro != scuro) {
      impostaTemaScuro(scuro);
      _tema = temaTryees();
      _temaScuro = scuro;
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Treeyes_Cityzen',
      theme: _tema,
      themeAnimationDuration: Duration.zero,
      home: _collegato
          ? NavigazionePrincipale(
              key: ValueKey(_sessione),
              inglese: _inglese,
              onLinguaCambiata: cambiaLingua,
              modoTema: _modoTema,
              onTemaCambiato: _cambiaTema,
              demo: CitizenApi.instance.demoMode,
              onCambiaCollegamento: () => setState(() => _collegato = false),
              // Demo ⇄ server con un tocco: si ricostruiscono tutte le schermate.
              onProfiloCambiato: () => setState(() => _sessione++),
            )
          : SchermataAccesso(
              s: Copie(_inglese),
              onLinguaCambiata: cambiaLingua,
              onCollegato: () => setState(() {
                _collegato = true;
                _sessione++;
              }),
            ),
    );
  }
}

class NavigazionePrincipale extends StatefulWidget {
  final bool inglese;
  final ValueChanged<bool> onLinguaCambiata;
  final ModoTema modoTema;
  final ValueChanged<ModoTema>? onTemaCambiato;
  final bool demo;
  /// Torna alla pagina di accesso per scegliere un altro server o la demo.
  final VoidCallback? onCambiaCollegamento;
  /// Chiamata dopo il passaggio diretto demo ⇄ server: l'app ricarica le schermate.
  final VoidCallback? onProfiloCambiato;

  const NavigazionePrincipale({
    super.key,
    required this.inglese,
    required this.onLinguaCambiata,
    this.modoTema = ModoTema.sistema,
    this.onTemaCambiato,
    this.demo = false,
    this.onCambiaCollegamento,
    this.onProfiloCambiato,
  });

  @override
  State<NavigazionePrincipale> createState() => _NavigazionePrincipaleState();
}

class _NavigazionePrincipaleState extends State<NavigazionePrincipale>
    with TickerProviderStateMixin {
  /// Schede della barra in basso. Segnala sta al centro: è l'azione principale.
  static const int pInizio = 0, pMappa = 1, pSegnala = 2, pAria = 3, pAssistente = 4;

  /// Colore di ogni sezione, nello stesso ordine delle pagine.
  static const List<Accento> _accenti = [
    Accento.verde,
    Accento.blu,
    Accento.arancio,
    Accento.acqua,
    Accento.viola,
  ];

  int _pagina = pInizio;
  /// Verso del cambio scheda: 1 verso destra, -1 verso sinistra.
  int _direzione = 1;
  /// 0 = barra in alto piena, 1 = ridotta (si scorre verso il basso).
  late final AnimationController _testata = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  /// Cresce a ogni segnalazione inviata: la mappa si ricarica.
  int _invii = 0;
  /// Avvisi attivi (per il pallino sulla campanella) e se almeno uno è importante.
  int _avvisiAttivi = 0;
  bool _avvisiUrgenti = false;
  Timer? _debounceAvvisi;
  late final AnimationController _transizione = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  StreamSubscription<Map<String, dynamic>>? _live;
  /// Dati ambientali condivisi da Home, schermata Ambiente e assistente.
  late final StatoAmbiente _ambiente = StatoAmbiente();
  /// Avvisi di pericolo già mostrati: lo stesso avviso non riapre la finestra.
  final Set<Object> _pericoliMostrati = {};
  bool _cambioProfilo = false;

  @override
  void initState() {
    super.initState();
    // Collegamento live attivo in tutta l'app, non solo nelle schede che lo usano:
    // un pericolo segnalato dal backend deve arrivare ovunque si trovi l'utente.
    CitizenApi.instance.connectLive();
    unawaited(_ambiente.ricarica());
    _ambiente.aggiornamentoPeriodico(_pagina == pInizio);
    unawaited(_contaAvvisi());
    _live = CitizenApi.instance.events.listen((e) {
      final tipo = e['type'];
      if (tipo == 'notice_created' || tipo == 'notice_ended' || tipo == 'park_status_changed') {
        _debounceAvvisi?.cancel();
        _debounceAvvisi = Timer(const Duration(milliseconds: 400), _contaAvvisi);
      }
      final dati = e['data'];
      if (dati is! Map) return;
      // environment_alert non è un danger_alert: solo il banner in Home (StatoAmbiente).
      if (e['type'] == 'danger_alert') {
        _mostraPericolo(Map<String, dynamic>.from(dati));
      } else if (e['type'] == 'notice_ended') {
        _pericoloRientrato(dati['notice_id']);
      }
    });
  }

  /// Avviso di pericolo mostrato in primo piano in questo momento e il contesto della sua finestra.
  Object? _pericoloAperto;
  BuildContext? _contestoPericolo;

  /// L'operatore ha riarmato l'allarme o chiuso la pratica: se la finestra di quel
  /// pericolo è ancora aperta si chiude e si avvisa che la situazione è rientrata.
  void _pericoloRientrato(Object? noticeId) {
    if (noticeId == null || noticeId != _pericoloAperto) return;
    final ctx = _contestoPericolo;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop(false);
    if (!mounted) return;
    final s = Copie(widget.inglese);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s.t('Pericolo rientrato: l’avviso è stato chiuso.', 'Danger over: the alert has been closed.')),
    ));
  }

  /// Conta gli avvisi attivi per il pallino della campanella.
  Future<void> _contaAvvisi() async {
    try {
      final avvisi = await CitizenApi.instance.getNotices();
      if (!mounted) return;
      setState(() {
        _avvisiAttivi = avvisi.length;
        _avvisiUrgenti = avvisi.any((a) => a['level'] == 'alert');
      });
    } catch (_) {
      // Senza server la campanella resta senza numero.
    }
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounceAvvisi?.cancel();
    _ambiente.dispose();
    _transizione.dispose();
    _testata.dispose();
    super.dispose();
  }

  Future<void> _mostraPericolo(Map<String, dynamic> dati) async {
    final id = dati['notice_id'] ?? '${dati['title']}|${dati['at']}';
    if (!mounted || !_pericoliMostrati.add(id)) return;
    final s = Copie(widget.inglese);
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    final titolo = (dati['title'] as String?)?.trim();
    final testoAvviso = (dati['body'] as String?)?.trim();
    _pericoloAperto = id;
    final vediAvvisi = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _contestoPericolo = ctx;
        return AlertDialog(
        backgroundColor: superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: coralloScuro, width: 2),
        ),
        icon: IconaTonda(Icons.warning_amber_rounded, colore: coralloScuro, sfondo: coralloChiaro, dimensione: 64),
        title: Semantics(
          liveRegion: true,
          child: Text(
            titolo == null || titolo.isEmpty ? s.t('Pericolo nel parco', 'Danger in the park') : titolo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: coralloScuro),
          ),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: coralloChiaro, borderRadius: BorderRadius.circular(12)),
            child: Text(
              s.t('AVVISO DI SICUREZZA', 'SAFETY ALERT'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: coralloScuro, letterSpacing: .8),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            testoAvviso == null || testoAvviso.isEmpty
                ? s.t('Evita la zona e segui le indicazioni del personale.', 'Avoid the area and follow staff instructions.')
                : testoAvviso,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4, color: testo),
          ),
          const SizedBox(height: 10),
          Text(
            s.t('In caso di emergenza chiama il 112.', 'In an emergency call 112.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testoSecondario),
          ),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('Ho capito', 'Got it')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: coralloScuro),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.notifications_active_rounded),
            label: Text(s.t('Vedi avvisi', 'See notices')),
          ),
        ],
      );
      },
    );
    if (_pericoloAperto == id) {
      _pericoloAperto = null;
      _contestoPericolo = null;
    }
    if (vediAvvisi == true && mounted) _apriAvvisi(s);
  }

  /// Passa da demo a server (o viceversa) senza aprire la tendina.
  /// Senza un server già scelto si apre la pagina di accesso per indicarlo.
  Future<void> _cambiaProfilo(bool demo) async {
    if (_cambioProfilo || demo == widget.demo) return;
    if (!demo && !CitizenApi.instance.haServer) {
      CitizenApi.instance.disconnectLive();
      widget.onCambiaCollegamento?.call();
      return;
    }
    setState(() => _cambioProfilo = true);
    CitizenApi.instance.disconnectLive();
    await CitizenApi.instance.setDemoMode(demo);
    if (!mounted) return;
    setState(() => _cambioProfilo = false);
    widget.onProfiloCambiato?.call();
  }

  void _vaiA(int indice) {
    // La tastiera della chat non resta aperta passando a un'altra scheda.
    if (indice != pAssistente) FocusManager.instance.primaryFocus?.unfocus();
    if (indice != _pagina) {
      HapticFeedback.selectionClick();
      setState(() {
        _direzione = indice > _pagina ? 1 : -1;
        _pagina = indice;
      });
      if (!MediaQuery.of(context).disableAnimations) _transizione.forward(from: 0);
      _testata.reverse();
    }
    // GET periodico dei dati ambientali solo mentre Home o Aria sono visibili.
    final conAria = indice == pInizio || indice == pAria;
    _ambiente.aggiornamentoPeriodico(conAria);
    if (conAria) unawaited(_ambiente.ricarica(silenzioso: true));
  }

  /// Pagina sopra le schede (o sopra la chat: tornando indietro la conversazione è ancora lì).
  /// Senza [titolo] la barra mostra solo la freccia: il titolo è già nella pagina.
  Future<void> _apriPagina(BuildContext ctx, String? titolo, Widget corpo) =>
      Navigator.of(ctx).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: titolo == null ? null : Text(titolo, style: const TextStyle(fontWeight: FontWeight.w800)),
            toolbarHeight: titolo == null ? 48 : null,
          ),
          body: SafeArea(top: false, child: corpo),
        ),
      ));

  Future<void> _apriAvvisi(Copie s, [BuildContext? ctx, int? evidenzia]) async {
    await _apriPagina(ctx ?? context, null, SchermataAvvisi(s: s, evidenzia: evidenzia));
    unawaited(_contaAvvisi());
  }

  void _apriIdee(Copie s, [BuildContext? ctx, int? evidenzia]) =>
      _apriPagina(ctx ?? context, null, SchermataIdee(s: s, evidenzia: evidenzia));

  /// Tocco su una fonte della risposta dell'assistente.
  void _apriFonte(BuildContext ctx, AssistantSource fonte, Copie s) {
    switch (fonte.type) {
      case TipiFonte.statoParco:
        Navigator.of(ctx).popUntil((r) => r.isFirst);
        _vaiA(pInizio);
      case TipiFonte.avviso:
        _apriAvvisi(s, ctx, fonte.id);
      case TipiFonte.idea:
        _apriIdee(s, ctx, fonte.id);
      case TipiFonte.miaSegnalazione || TipiFonte.segnalazione:
        final mia = fonte.type == TipiFonte.miaSegnalazione;
        _apriPagina(
          ctx,
          mia ? s.t('Le mie segnalazioni', 'My reports') : s.t('Segnalazioni', 'Reports'),
          SchermataSegnalazioni(s: s, apri: fonte.id, soloMie: mia),
        );
      case TipiFonte.ambiente:
        final metrica = fonte.metric;
        if (metrica == null && fonte.stationId == null) {
          Navigator.of(ctx).popUntil((r) => r.isFirst);
          _vaiA(pAria);
        } else if (metrica == null) {
          apriAmbiente(ctx, _ambiente, s, stazione: fonte.stationId);
        } else {
          apriGrafico(ctx, _ambiente, s, metrica: metrica, stazione: fonte.stationId);
        }
      case TipiFonte.categorie:
        Navigator.of(ctx).popUntil((r) => r.isFirst);
        _vaiA(pSegnala);
    }
  }

  /// Pannello Impostazioni: lingua, tema e collegamento (demo o server).
  Future<void> _apriImpostazioni() async {
    var inglese = widget.inglese;
    var modo = widget.modoTema;
    final demo = widget.demo;
    final server = CitizenApi.instance.baseUrl;
    final cambia = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, aggiorna) {
          final s = Copie(inglese);
          Widget titolo(String t) => Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text(
                  t.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: testoSecondario, letterSpacing: .9),
                ),
              );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IconaTonda(Icons.tune_rounded, colore: foresta, sfondo: menta, dimensione: 44),
                    const SizedBox(width: 12),
                    Text(
                      s.t('Impostazioni', 'Settings'),
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: testo, letterSpacing: -.3),
                    ),
                  ]),
                  titolo(s.t('Lingua', 'Language')),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('🇮🇹  Italiano')),
                      ButtonSegment(value: true, label: Text('🇬🇧  English')),
                    ],
                    selected: {inglese},
                    onSelectionChanged: (v) {
                      aggiorna(() => inglese = v.first);
                      widget.onLinguaCambiata(v.first);
                    },
                  ),
                  titolo(s.t('Tema', 'Theme')),
                  SegmentedButton<ModoTema>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ModoTema.sistema,
                        icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                        label: Text(s.t('Sistema', 'System')),
                      ),
                      ButtonSegment(
                        value: ModoTema.chiaro,
                        icon: const Icon(Icons.light_mode_rounded, size: 18),
                        label: Text(s.t('Chiaro', 'Light')),
                      ),
                      ButtonSegment(
                        value: ModoTema.scuro,
                        icon: const Icon(Icons.dark_mode_rounded, size: 18),
                        label: Text(s.t('Scuro', 'Dark')),
                      ),
                    ],
                    selected: {modo},
                    onSelectionChanged: (v) {
                      aggiorna(() => modo = v.first);
                      widget.onTemaCambiato?.call(v.first);
                    },
                  ),
                  if (widget.onCambiaCollegamento != null) ...[
                    titolo(s.t('Dati', 'Data')),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.science_rounded, size: 18),
                          label: Text(s.t('Demo', 'Demo')),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.cloud_done_rounded, size: 18),
                          label: Text(s.t('Server', 'Server')),
                        ),
                      ],
                      selected: {demo},
                      onSelectionChanged: (v) {
                        Navigator.of(ctx).pop(false);
                        _cambiaProfilo(v.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(demo ? Icons.info_outline_rounded : Icons.dns_rounded, size: 18, color: testoSecondario),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          demo ? s.t('Dati simulati, nulla viene inviato.', 'Simulated data, nothing is sent.') : server,
                          style: TextStyle(fontSize: 13.5, color: testoSecondario),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(s.t('Cambia server', 'Change server')),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    if (cambia == true) {
      CitizenApi.instance.disconnectLive();
      widget.onCambiaCollegamento?.call();
    }
  }

  /// Pulsante tondo della barra in alto (tema, impostazioni, avvisi).
  Widget _tondo({required String tooltip, required VoidCallback onPressed, required Widget icona}) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: superficie,
          side: BorderSide(color: bordo),
          minimumSize: const Size(40, 40),
          fixedSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
        icon: icona,
      );

  /// Piccolo segnale «DEMO» quando i dati sono simulati: un tocco apre le impostazioni.
  Widget _badgeDemo(Copie s) {
    if (!widget.demo && !_cambioProfilo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        label: s.t('Modalità demo, apri le impostazioni', 'Demo mode, open settings'),
        excludeSemantics: true,
        child: Material(
          color: lavandaChiaro,
          shape: StadiumBorder(side: BorderSide(color: lavanda.withValues(alpha: .35))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _apriImpostazioni,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_cambioProfilo)
                  SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: lavanda))
                else
                  Icon(Icons.science_rounded, size: 14, color: lavanda),
                const SizedBox(width: 4),
                Text('DEMO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: lavanda, letterSpacing: .6)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Interruttore del tema: un tocco passa da chiaro a scuro e viceversa.
  Widget _interruttoreTema(Copie s) {
    final scuro = temaScuro;
    return _tondo(
      tooltip: scuro ? s.t('Passa al tema chiaro', 'Switch to light theme') : s.t('Passa al tema scuro', 'Switch to dark theme'),
      onPressed: () {
        HapticFeedback.selectionClick();
        widget.onTemaCambiato?.call(scuro ? ModoTema.chiaro : ModoTema.scuro);
      },
      icona: AnimatedSwitcher(
        duration: durata(context, 380),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (figlio, a) => RotationTransition(
          turns: Tween<double>(begin: -.35, end: 0).animate(a),
          child: ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: figlio)),
        ),
        child: Icon(
          scuro ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(scuro),
          size: 20,
          color: scuro ? sole : foresta,
        ),
      ),
    );
  }

  /// Campanella degli avvisi nella barra in alto, con il numero di quelli attivi
  /// (rosso se almeno uno è importante).
  Widget _campanella(Copie s) {
    final etichetta = _avvisiAttivi == 0
        ? s.t('Avvisi del parco', 'Park notices')
        : s.t('Avvisi del parco: $_avvisiAttivi attivi', 'Park notices: $_avvisiAttivi active');
    return _tondo(
      tooltip: etichetta,
      onPressed: () => _apriAvvisi(s),
      icona: Badge(
        isLabelVisible: _avvisiAttivi > 0,
        backgroundColor: _avvisiUrgenti ? coralloScuro : lavanda,
        label: Text('$_avvisiAttivi'),
        child: Icon(
          _avvisiAttivi > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
          color: _avvisiUrgenti ? coralloScuro : foresta,
          size: 21,
        ),
      ),
    );
  }

  /// La barra in alto si riduce quando si scorre verso il basso e torna
  /// piena scorrendo verso l'alto. Solo sulle pagine che scorrono in verticale.
  bool _suScorrimento(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (_pagina == pMappa || _pagina == pAssistente) return false;
    final delta = n.scrollDelta ?? 0;
    if (n.metrics.pixels <= 8 || delta < -6) {
      if (_testata.value > 0 && _testata.status != AnimationStatus.reverse) _testata.reverse();
    } else if (delta > 6 && n.metrics.pixels > 40) {
      if (_testata.value < 1 && _testata.status != AnimationStatus.forward) _testata.forward();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = Copie(widget.inglese);
    final pagine = [
      SchermataInizio(
        key: ValueKey('inizio-$_invii'),
        s: s,
        ambiente: _ambiente,
        onMappa: () => _vaiA(pMappa),
        onAria: () => _vaiA(pAria),
        onIdee: () => _apriIdee(s),
        onAvvisi: () => _apriAvvisi(s),
        onMieSegnalazioni: () => _apriPagina(
          context,
          s.t('Le mie segnalazioni', 'My reports'),
          SchermataSegnalazioni(s: s, soloMie: true),
        ),
      ),
      SchermataSegnalazioni(key: ValueKey('mappa-$_invii'), s: s),
      SchermataSegnalazione(
        s: s,
        onInviata: () {
          // La mappa si ricarica e mostra subito la nuova segnalazione.
          setState(() => _invii++);
          _vaiA(pMappa);
        },
      ),
      SchermataAmbiente(stato: _ambiente, s: s, incorporata: true),
      SchermataAssistente(s: s, incorporata: true, onFonte: (ctx, fonte) => _apriFonte(ctx, fonte, s)),
    ];
    final curva = CurvedAnimation(parent: _transizione, curve: Curves.easeOutCubic);

    // Corpo e barra in basso si costruiscono qui: l'animazione della barra in
    // alto ricostruisce solo lo Scaffold, non le pagine.
    final corpo = SafeArea(
      top: false,
      bottom: false,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _suScorrimento,
        child: FadeTransition(
          opacity: curva,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(.06 * _direzione, 0), end: Offset.zero).animate(curva),
            child: IndexedStack(index: _pagina, children: pagine),
          ),
        ),
      ),
    );
    final barra = BarraSchede(
      selezionata: _pagina,
      centrale: pSegnala,
      accenti: _accenti,
      onSeleziona: _vaiA,
      voci: [
        VoceBarra(Icons.home_outlined, Icons.home_rounded, s.t('Inizio', 'Home')),
        VoceBarra(Icons.map_outlined, Icons.map_rounded, s.t('Mappa', 'Map')),
        VoceBarra(Icons.add_location_alt_rounded, Icons.add_location_alt_rounded, s.t('Segnala', 'Report')),
        VoceBarra(Icons.air_rounded, Icons.air_rounded, s.t('Aria', 'Air')),
        VoceBarra(Icons.forum_outlined, Icons.forum_rounded, nomeAssistente),
      ],
    );
    final azioni = [
      _badgeDemo(s),
      _interruttoreTema(s),
      const SizedBox(width: 6),
      _tondo(
        tooltip: s.t('Impostazioni', 'Settings'),
        onPressed: _apriImpostazioni,
        icona: Icon(Icons.tune_rounded, size: 20, color: foresta),
      ),
      const SizedBox(width: 6),
      _campanella(s),
      const SizedBox(width: 12),
    ];

    return AnimatedBuilder(
      animation: _testata,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_testata.value);
        double tra(double a, double b) => a + (b - a) * t;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            toolbarHeight: tra(64, 52),
            backgroundColor: Color.lerp(sfondo, superficie, t),
            shape: Border(bottom: BorderSide(color: bordo.withValues(alpha: t))),
            // Marchio su due righe (Treeyes / CITYZEN) che si rimpicciolisce
            // scorrendo e quando lo spazio è poco, senza mai troncarsi.
            title: SizedBox(
              height: tra(42, 30),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('Assets/logo_treeyes.png', height: 40, semanticLabel: 'Treeyes_Cityzen'),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Treeyes',
                          style: TextStyle(
                            fontSize: 23,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: forestaScura,
                            letterSpacing: -.4,
                          ),
                        ),
                        Text(
                          'CITYZEN',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: foresta,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: azioni,
          ),
          body: corpo,
          bottomNavigationBar: barra,
        );
      },
    );
  }
}

/// Una voce della barra in basso.
class VoceBarra {
  final IconData icona;
  final IconData iconaAttiva;
  final String etichetta;
  const VoceBarra(this.icona, this.iconaAttiva, this.etichetta);
}

/// Barra delle schede in basso: un indicatore colorato scivola sotto la voce
/// aperta e la voce [centrale] è un pulsante pieno in rilievo (Segnala).
class BarraSchede extends StatelessWidget {
  final int selezionata;
  final int centrale;
  final List<VoceBarra> voci;
  final List<Accento> accenti;
  final ValueChanged<int> onSeleziona;

  const BarraSchede({
    super.key,
    required this.selezionata,
    required this.centrale,
    required this.voci,
    required this.accenti,
    required this.onSeleziona,
  });

  @override
  Widget build(BuildContext context) {
    final basso = MediaQuery.paddingOf(context).bottom;
    final accento = accenti[selezionata];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: superficie,
        border: Border(top: BorderSide(color: bordo)),
        boxShadow: [BoxShadow(color: ombra, blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: basso),
        child: SizedBox(
          height: 76,
          child: LayoutBuilder(
            builder: (context, vincoli) {
              final larghezza = vincoli.maxWidth / voci.length;
              const lIndicatore = 60.0;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: durata(context, 420),
                    curve: Curves.easeOutBack,
                    left: selezionata * larghezza + (larghezza - lIndicatore) / 2,
                    top: 10,
                    width: lIndicatore,
                    height: 32,
                    child: AnimatedOpacity(
                      duration: durata(context, 200),
                      opacity: selezionata == centrale ? 0 : 1,
                      child: AnimatedContainer(
                        duration: durata(context, 300),
                        decoration: BoxDecoration(color: accento.tinta, borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final (i, v) in voci.indexed)
                        Expanded(
                          child: i == centrale
                              ? _VoceCentrale(
                                  voce: v,
                                  selezionata: i == selezionata,
                                  accento: accenti[i],
                                  onTap: () => onSeleziona(i),
                                )
                              : _Voce(
                                  voce: v,
                                  selezionata: i == selezionata,
                                  accento: accenti[i],
                                  onTap: () => onSeleziona(i),
                                ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Voce extends StatelessWidget {
  final VoceBarra voce;
  final bool selezionata;
  final Accento accento;
  final VoidCallback onTap;
  const _Voce({required this.voce, required this.selezionata, required this.accento, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colore = selezionata ? accento.forte : testoSecondario;
    return Semantics(
      button: true,
      selected: selezionata,
      label: voce.etichetta,
      excludeSemantics: true,
      child: Premibile(
        onTap: onTap,
        child: Column(
          children: [
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Center(
                child: AnimatedSwitcher(
                  duration: durata(context, 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (figlio, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: figlio)),
                  child: Icon(
                    selezionata ? voce.iconaAttiva : voce.icona,
                    key: ValueKey(selezionata),
                    size: 24,
                    color: colore,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: durata(context, 220),
              style: TextStyle(
                fontSize: 12,
                fontWeight: selezionata ? FontWeight.w800 : FontWeight.w600,
                color: colore,
              ),
              child: Text(voce.etichetta, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsante centrale pieno: l'azione principale dell'app.
class _VoceCentrale extends StatelessWidget {
  final VoceBarra voce;
  final bool selezionata;
  final Accento accento;
  final VoidCallback onTap;
  const _VoceCentrale({required this.voce, required this.selezionata, required this.accento, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selezionata,
        label: voce.etichetta,
        excludeSemantics: true,
        child: Premibile(
          onTap: onTap,
          scala: .88,
          child: Column(
            children: [
              const SizedBox(height: 2),
              AnimatedScale(
                scale: selezionata ? 1.06 : 1,
                duration: durata(context, 320),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: durata(context, 260),
                  width: 56,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF26B3F), Color(0xFFD9431C)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: selezionata ? superficie : Colors.transparent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: corallo.withValues(alpha: selezionata ? .55 : .35),
                        blurRadius: selezionata ? 18 : 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(voce.icona, color: Colors.white, size: 25),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                voce.etichetta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accento.forte),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inizio
// ─────────────────────────────────────────────────────────────────────────────

class SchermataInizio extends StatefulWidget {
  final Copie s;
  final VoidCallback? onMappa;
  /// Apre la scheda «Aria» (senza, si apre la schermata Ambiente sopra la Home).
  final VoidCallback? onAria;
  final VoidCallback? onIdee;
  final VoidCallback? onAvvisi;
  final VoidCallback? onMieSegnalazioni;
  /// Dati ambientali (scheda di benvenuto e banner di allerta); senza, non compaiono.
  final StatoAmbiente? ambiente;

  const SchermataInizio({
    super.key,
    required this.s,
    this.onMappa,
    this.onAria,
    this.onIdee,
    this.onAvvisi,
    this.onMieSegnalazioni,
    this.ambiente,
  });

  @override
  State<SchermataInizio> createState() => _SchermataInizioState();
}

class _SchermataInizioState extends State<SchermataInizio> {
  /// Cresce a ogni pull-to-refresh: l'anteprima della mappa si ricarica.
  int _aggiornamenti = 0;

  Future<void> _aggiorna() async {
    setState(() => _aggiornamenti++);
    await widget.ambiente?.ricarica(silenzioso: true);
  }

  void _apriAmbiente() {
    if (widget.onAria != null) return widget.onAria!();
    final ambiente = widget.ambiente;
    if (ambiente != null) apriAmbiente(context, ambiente, widget.s);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final ambiente = widget.ambiente;
    final scorciatoie = [
      _ScorciatoiaHome(
        icona: Icons.lightbulb_rounded,
        etichetta: s.t('Idee', 'Ideas'),
        accento: Accento.giallo,
        onTap: widget.onIdee,
      ),
      _ScorciatoiaHome(
        icona: Icons.campaign_rounded,
        etichetta: s.t('Avvisi', 'Notices'),
        accento: Accento.blu,
        onTap: widget.onAvvisi,
      ),
      if (widget.onMieSegnalazioni != null)
        _ScorciatoiaHome(
          icona: Icons.person_pin_circle_rounded,
          etichetta: s.t('Le mie segnalazioni', 'My reports'),
          accento: Accento.arancio,
          onTap: widget.onMieSegnalazioni,
        ),
    ];

    // La Home riempie lo schermo: la mappa prende tutto lo spazio che resta.
    // Su schermi bassi la pagina ha un'altezza minima e scorre.
    return RefreshIndicator(
      onRefresh: _aggiorna,
      child: LayoutBuilder(
        builder: (context, vincoli) {
          final stretto = vincoli.maxWidth < 380;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SizedBox(
                  height: vincoli.maxHeight < 640 ? 640 : vincoli.maxHeight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(stretto ? 16 : 20, 4, stretto ? 16 : 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Appare(child: SchedaBenvenuto(s: s, ambiente: ambiente, onAria: _apriAmbiente)),
                        if (ambiente != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: BannerAllerteAmbiente(stato: ambiente, s: s, onApri: _apriAmbiente),
                          ),
                        const SizedBox(height: 12),
                        Appare(
                          indice: 1,
                          child: Row(
                            children: [
                              for (final (i, sc) in scorciatoie.indexed) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(child: sc),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Appare(
                            indice: 2,
                            child: AnteprimaMappa(
                              key: ValueKey(_aggiornamenti),
                              s: s,
                              onApri: widget.onMappa,
                              altezza: double.infinity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Scheda di benvenuto in cima alla Home: saluto in base all'ora e, se il
/// parco ha sensori, il giudizio sull'aria con la temperatura.
class SchedaBenvenuto extends StatelessWidget {
  final Copie s;
  final StatoAmbiente? ambiente;
  final VoidCallback onAria;
  const SchedaBenvenuto({super.key, required this.s, required this.ambiente, required this.onAria});

  /// Saluto in base all'ora: la Home si apre ogni giorno, non è una vetrina.
  String _saluto() {
    final ora = DateTime.now().hour;
    if (ora >= 5 && ora < 13) return s.t('Buongiorno', 'Good morning');
    if (ora >= 13 && ora < 18) return s.t('Buon pomeriggio', 'Good afternoon');
    return s.t('Buonasera', 'Good evening');
  }

  IconData _iconaOra() {
    final ora = DateTime.now().hour;
    if (ora >= 6 && ora < 18) return Icons.wb_sunny_rounded;
    if (ora >= 18 && ora < 21) return Icons.wb_twilight_rounded;
    return Icons.nightlight_round;
  }

  @override
  Widget build(BuildContext context) {
    final colori = temaScuro
        ? const [Color(0xFF123A2A), Color(0xFF1B5A3F)]
        : const [Color(0xFF17694A), Color(0xFF2FA36B)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colori),
        ),
        child: Stack(
          children: [
            // Cerchi decorativi: danno profondità senza immagini.
            Positioned(right: -40, top: -50, child: _cerchio(150, .08)),
            Positioned(right: 50, bottom: -60, child: _cerchio(110, .06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            _saluto(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                      ),
                      _IconaOscillante(icona: _iconaOra()),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.t('Ecco il parco in questo momento', 'Here is the park right now'),
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .85)),
                  ),
                  if (ambiente != null) _riquadroAria(ambiente!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cerchio(double d, double alfa) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alfa)),
      );

  /// Riga «vetro» con il giudizio sull'aria e la temperatura che sale fino al valore.
  Widget _riquadroAria(StatoAmbiente stato) => ListenableBuilder(
        listenable: stato,
        builder: (context, _) {
          final a = stato.ambiente;
          if (a == null || a.stations.isEmpty) return const SizedBox.shrink();
          final st = a.stations.first;
          final aggiornata = st.fresh;
          final titolo = aggiornata ? testoAria(a.airQuality, s) : s.t('Dati non aggiornati', 'Data not up to date');
          final temp = st.lettura(Metriche.temperatura);
          final mTemp = stato.metrica(Metriche.temperatura);
          final livello = accentoLivello(a.airQuality.level);
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Semantics(
              button: true,
              label: '${s.t('Aria nel parco', 'Air in the park')}: $titolo'
                  '${temp == null ? '' : '. ${formattaValore(temp.value, mTemp, s)}'}',
              excludeSemantics: true,
              child: Premibile(
                onTap: onAria,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: .22)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: aggiornata ? livello.base : Colors.white54,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titolo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              s.t('Aria nel parco · ${quandoLettura(st.lastSeen, s)}', 'Park air · ${quandoLettura(st.lastSeen, s)}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: .8)),
                            ),
                          ],
                        ),
                      ),
                      if (temp?.value case final valore?) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.thermostat_rounded, size: 20, color: Colors.white),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: valore - 6, end: valore),
                          duration: durata(context, 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Text(
                            formattaValore(v, mTemp, s),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Icona del momento della giornata che oscilla piano, come appesa.
class _IconaOscillante extends StatefulWidget {
  final IconData icona;
  const _IconaOscillante({required this.icona});

  @override
  State<_IconaOscillante> createState() => _IconaOscillanteState();
}

class _IconaOscillanteState extends State<_IconaOscillante> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RotationTransition(
          turns: Tween<double>(begin: -.03, end: .03).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), shape: BoxShape.circle),
            child: Icon(widget.icona, color: const Color(0xFFFFE08A), size: 24),
          ),
        ),
      );
}

/// Scorciatoia della Home: icona e una o due parole.
class _ScorciatoiaHome extends StatelessWidget {
  final IconData icona;
  final String etichetta;
  final Accento accento;
  final VoidCallback? onTap;

  const _ScorciatoiaHome({
    required this.icona,
    required this.etichetta,
    required this.accento,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: etichetta,
        onTap: onTap,
        excludeSemantics: true,
        child: Premibile(
          onTap: onTap,
          child: Container(
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: accento.tinta,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accento.base.withValues(alpha: .22)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icona, size: 26, color: accento.forte),
                const SizedBox(height: 5),
                Text(
                  etichetta,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w800, color: accento.forte),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Nuova segnalazione
// ─────────────────────────────────────────────────────────────────────────────

class SchermataSegnalazione extends StatefulWidget {
  final Copie s;
  /// Chiamata quando l'utente, dopo l'invio, vuole vedere la segnalazione sulla mappa.
  final VoidCallback? onInviata;
  const SchermataSegnalazione({super.key, required this.s, this.onInviata});

  @override
  State<SchermataSegnalazione> createState() => _SchermataSegnalazioneState();
}

class _SchermataSegnalazioneState extends State<SchermataSegnalazione> {
  final TextEditingController _descrizione = TextEditingController();

  int _passaggio = 0;
  /// 1 avanti, -1 indietro: i passaggi scorrono nella direzione giusta.
  int _versoPassaggio = 1;
  /// Cima della pagina: a ogni cambio di passaggio si torna lì.
  final GlobalKey _cima = GlobalKey();

  void _tornaInCima() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _cima.currentContext;
        if (ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(ctx, duration: durata(ctx, 320), curve: Curves.easeOutCubic);
      });
  String? _categoria;
  String _gravita = 'media';
  String? _errore;

  /// Categorie usate finché il backend non risponde: gli id sono i codici del backend.
  static const List<_CategoriaSegnalazione> _categorieBase = [
    _CategoriaSegnalazione(
      id: 'waste',
      nomeIt: 'Cestini e rifiuti',
      nomeEn: 'Bins and waste',
      icona: Icons.delete_outline_rounded,
      accento: Accento.blu,
    ),
    _CategoriaSegnalazione(
      id: 'green',
      nomeIt: 'Verde e piante',
      nomeEn: 'Trees and plants',
      icona: Icons.park_outlined,
      accento: Accento.verde,
    ),
    _CategoriaSegnalazione(
      id: 'furniture',
      nomeIt: 'Arredi e panchine',
      nomeEn: 'Benches and furniture',
      icona: Icons.chair_outlined,
      accento: Accento.arancio,
    ),
    _CategoriaSegnalazione(
      id: 'lighting',
      nomeIt: 'Illuminazione',
      nomeEn: 'Lighting',
      icona: Icons.lightbulb_outline_rounded,
      accento: Accento.giallo,
    ),
    _CategoriaSegnalazione(
      id: 'other',
      nomeIt: 'Altro',
      nomeEn: 'Other',
      icona: Icons.more_horiz_rounded,
      accento: Accento.viola,
    ),
  ];

  List<_CategoriaSegnalazione> _categorie = _categorieBase;

  @override
  void initState() {
    super.initState();
    unawaited(_caricaCategorie());
  }

  Future<void> _caricaCategorie() async {
    try {
      final rows = await CitizenApi.instance.getCategories(kind: 'problem');
      if (!mounted || rows.isEmpty) return;
      setState(() => _categorie = rows.map(_CategoriaSegnalazione.fromBackend).toList());
    } catch (_) {
      // Backend non raggiungibile: restano le categorie di base.
    }
  }

  @override
  void dispose() {
    _descrizione.dispose();
    super.dispose();
  }

  void _mostraErrore(String messaggio) {
    setState(() => _errore = messaggio);
  }

  void _vaiAvanti() {
    final s = widget.s;
    if (_passaggio == 0 && _categoria == null) {
      _mostraErrore(
        s.t(
          'Seleziona una categoria per continuare.',
          'Choose a category to continue.',
        ),
      );
      return;
    }

    if (_passaggio < 2) {
      setState(() {
        _errore = null;
        _versoPassaggio = 1;
        _passaggio++;
      });
      _tornaInCima();
      // La posizione si cerca da sola: l'utente non deve premere nulla.
      if (_passaggio == 1 && _posizione == null && !_caricamentoGps) unawaited(_rilevaPosizione());
    } else {
      _mostraConferma();
    }
  }

  void _tornaIndietro() {
    if (_passaggio > 0) {
      setState(() {
        _errore = null;
        _versoPassaggio = -1;
        _passaggio--;
      });
      _tornaInCima();
    }
  }

  XFile? _foto;
  /// Lettura dell'anteprima fatta una sola volta, così non lampeggia a ogni aggiornamento.
  Future<Uint8List>? _anteprimaFoto;
  Position? _posizione;
  bool _caricamentoGps = false;
  bool _invioInCorso = false;

  Future<void> _selezionaFoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 82, maxWidth: 1600);
      if (!mounted || file == null) return;
      setState(() { _foto = file; _anteprimaFoto = file.readAsBytes(); _errore = null; });
    } catch (_) {
      _mostraErrore(widget.s.t(
        'Non è stato possibile aprire la fotocamera o la galleria. Controlla i permessi dell’app.',
        'Could not open the camera or gallery. Check the app permissions.',
      ));
    }
  }

  void _rimuoviFoto() => setState(() { _foto = null; _anteprimaFoto = null; });

  /// Cambia a ogni rilevamento: la mappa si ricrea centrata sul nuovo punto.
  int _rilevamenti = 0;

  Position _posizioneDa(double lat, double lon) => Position(
        latitude: lat, longitude: lon, timestamp: DateTime.now(), accuracy: 5, altitude: 120,
        altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0, isMocked: true,
      );

  Future<void> _rilevaPosizione() async {
    setState(() { _caricamentoGps = true; _errore = null; });
    if (CitizenApi.instance.demoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final p = CitizenApi.instance.posizioneSimulata();
      if (mounted) setState(() { _posizione = _posizioneDa(p.lat, p.lon); _rilevamenti++; _caricamentoGps = false; });
      return;
    }
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception(widget.s.t('Attiva la posizione (GPS) del telefono e riprova.', 'Turn on your phone’s location (GPS) and try again.'));
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception(widget.s.t(
          'Per inviare la segnalazione serve sapere dove ti trovi: consenti l’accesso alla posizione.',
          'To send the report we need to know where you are: allow location access.',
        ));
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() { _posizione = position; _rilevamenti++; });
    } catch (e) {
      if (mounted) _mostraErrore(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _caricamentoGps = false);
    }
  }

  Future<void> _mostraConferma() async {
    final s = widget.s;
    if (_posizione == null) {
      _mostraErrore(s.t('Manca la posizione: tocca «Trova la mia posizione».', 'The location is missing: tap “Find my location”.'));
      setState(() {
        _versoPassaggio = -1;
        _passaggio = 1;
      });
      return;
    }
    setState(() { _invioInCorso = true; _errore = null; });
    try {
      final categoria = _categoria ?? 'other';
      final nomeCategoria = _categorie
          .firstWhere((c) => c.id == categoria, orElse: () => _categorieBase.last)
          .nomeIt;
      final descrizione = _descrizione.text.trim().length >= 10
          ? _descrizione.text.trim()
          : 'Problema segnalato: $nomeCategoria';
      final result = await CitizenApi.instance.createProblemReport(
        category: categoria,
        description: descrizione,
        priority: _gravita == 'bassa' ? 'low' : _gravita == 'alta' ? 'high' : 'medium',
        latitude: _posizione!.latitude,
        longitude: _posizione!.longitude,
        photoBytes: _foto == null ? null : await _foto!.readAsBytes(),
        photoName: _foto?.name,
      );
      if (!mounted) return;
      final vediMappa = await mostraSegnalazioneInviata(
        context,
        s: s,
        codice: '${result['code'] ?? result['id']}',
        stato: result['status_label']?.toString(),
        conMappa: widget.onInviata != null,
      );
      if (!mounted) return;
      setState(() {
        _passaggio = 0; _versoPassaggio = -1; _categoria = null; _gravita = 'media';
        _descrizione.clear(); _errore = null; _foto = null; _anteprimaFoto = null; _posizione = null;
      });
      if (vediMappa == true) widget.onInviata?.call();
    } catch (e) {
      if (mounted) _mostraErrore(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _invioInCorso = false);
    }
  }

  // ── Indicatore dei passaggi ────────────────────────────────────────────────

  Widget _indicatorePassaggi(Copie s) {
    final nomi = [
      s.t('Cosa', 'What'),
      s.t('Dove e foto', 'Where and photo'),
      s.t('Invia', 'Send'),
    ];

    Widget linea(bool attiva) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: bordo)),
                AnimatedFractionallySizedBox(
                  duration: durata(context, 420),
                  curve: Curves.easeInOutCubic,
                  widthFactor: attiva ? 1 : 0,
                  heightFactor: 1,
                  alignment: _versoPassaggio > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: ColoredBox(color: foresta),
                ),
              ],
            ),
          ),
        );

    Widget cerchio(int i) {
      final completato = i < _passaggio;
      final corrente = i == _passaggio;
      return AnimatedContainer(
        duration: durata(context, 300),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completato || corrente ? foresta : superficie,
          border: Border.all(color: completato || corrente ? foresta : bordoForte, width: 1.5),
          boxShadow: corrente ? [BoxShadow(color: foresta.withValues(alpha: .33), blurRadius: 0, spreadRadius: 4)] : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: durata(context, 320),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (figlio, a) => ScaleTransition(scale: a, child: figlio),
            child: completato
                ? const Icon(Icons.check_rounded, key: ValueKey('fatto'), size: 19, color: Colors.white)
                : Text(
                    '${i + 1}',
                    key: ValueKey('n$i'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: corrente ? Colors.white : testoSecondario,
                    ),
                  ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: s.t(
        'Passaggio ${_passaggio + 1} di 3: ${nomi[_passaggio]}',
        'Step ${_passaggio + 1} of 3: ${nomi[_passaggio]}',
      ),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            3,
            (i) => Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: i == 0 ? const SizedBox() : linea(i <= _passaggio)),
                      const SizedBox(width: 6),
                      cerchio(i),
                      const SizedBox(width: 6),
                      Expanded(child: i == 2 ? const SizedBox() : linea(i < _passaggio)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nomi[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: i == _passaggio ? FontWeight.w800 : FontWeight.w600,
                      color: i == _passaggio ? foresta : i < _passaggio ? testo : testoSecondario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intestazionePassaggio(String titolo, String descrizione) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titolo, style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.3)),
          const SizedBox(height: 6),
          Text(descrizione, style: TextStyle(fontSize: 15, height: 1.45, color: testoSecondario)),
          const SizedBox(height: 18),
        ],
      );

  Widget _etichettaCampo(String testoCampo, [String? aiuto]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(testoCampo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: testo)),
            if (aiuto != null) ...[
              const SizedBox(height: 3),
              Text(aiuto, style: TextStyle(fontSize: 13, height: 1.4, color: testoSecondario)),
            ],
          ],
        ),
      );

  // ── Passaggio 1: problema ──────────────────────────────────────────────────

  Widget _schedaCategoria(_CategoriaSegnalazione categoria, Copie s) {
    final selezionata = _categoria == categoria.id;
    final nome = s.t(categoria.nomeIt, categoria.nomeEn);
    final accento = categoria.accento;

    void selezionaCategoria() {
      HapticFeedback.selectionClick();
      setState(() {
        _categoria = categoria.id;
        _errore = null;
      });
      // Scelta fatta: si passa da soli al passaggio successivo.
      Future<void>.delayed(durata(context, 380), () {
        if (mounted && _passaggio == 0 && _categoria == categoria.id) _vaiAvanti();
      });
    }

    return Semantics(
      container: true,
      button: true,
      selected: selezionata,
      label: nome,
      hint: s.t(
        'Tocca due volte per selezionare questa categoria.',
        'Double tap to select this category.',
      ),
      onTap: selezionaCategoria,
      child: ExcludeSemantics(
        child: Premibile(
          onTap: selezionaCategoria,
          child: AnimatedContainer(
            duration: durata(context, 220),
            curve: Curves.easeOutCubic,
            height: 104,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            decoration: BoxDecoration(
              color: selezionata ? accento.tinta : superficie,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selezionata ? accento.base : bordo,
                width: selezionata ? 2 : 1,
              ),
              boxShadow: selezionata
                  ? [BoxShadow(color: accento.base.withValues(alpha: .22), blurRadius: 16, offset: const Offset(0, 6))]
                  : [BoxShadow(color: ombra, blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    AnimatedScale(
                      scale: selezionata ? 1.14 : 1,
                      duration: durata(context, 320),
                      curve: Curves.easeOutBack,
                      child: IconaTonda(
                        categoria.icona,
                        colore: accento.forte,
                        sfondo: selezionata ? superficie : accento.tinta,
                        dimensione: 42,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      nome,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: testo,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: selezionata ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: -4,
                  right: -2,
                  child: AnimatedScale(
                    scale: selezionata ? 1 : 0,
                    duration: durata(context, 260),
                    curve: Curves.easeOutBack,
                    child: Icon(Icons.check_circle_rounded, color: accento.forte, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selettoreGravita(Copie s) {
    const livelli = [
      ('bassa', 'Bassa', 'Low', foglia),
      ('media', 'Media', 'Medium', sole),
      ('alta', 'Alta', 'High', corallo),
    ];

    return Row(
      children: [
        for (final (i, livello) in livelli.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(builder: (context) {
              final selezionata = _gravita == livello.$1;
              final nome = s.t(livello.$2, livello.$3);
              return Semantics(
                button: true,
                selected: selezionata,
                label: nome,
                onTap: () => setState(() => _gravita = livello.$1),
                excludeSemantics: true,
                child: AnimatedContainer(
                  duration: durata(context, 180),
                  decoration: BoxDecoration(
                    color: selezionata ? livello.$4.withValues(alpha: .14) : superficie,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selezionata ? livello.$4 : bordo, width: selezionata ? 1.8 : 1),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _gravita = livello.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: durata(context, 180),
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: livello.$4,
                                boxShadow: selezionata
                                    ? [BoxShadow(color: livello.$4.withValues(alpha: .35), spreadRadius: 3)]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                nome,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: selezionata ? FontWeight.w800 : FontWeight.w600,
                                  color: testo,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _passaggioProblema(Copie s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intestazionePassaggio(
          s.t('Cosa hai notato?', 'What did you notice?'),
          s.t('Tocca la voce che descrive meglio il problema.', 'Tap the option that best describes the problem.'),
        ),
        LayoutBuilder(
          builder: (builderContext, constraints) {
            final colonne = constraints.maxWidth < 330 ? 2 : 3;
            final larghezza = (constraints.maxWidth - 10 * (colonne - 1)) / colonne;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, categoria) in _categorie.indexed)
                  SizedBox(width: larghezza, child: Appare(indice: i, child: _schedaCategoria(categoria, s))),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Riquadro(
          icona: Icons.shield_outlined,
          messaggio: s.t(
            'La segnalazione è anonima. Non fotografare persone e non scrivere dati personali.',
            'The report is anonymous. Do not photograph people or include personal data.',
          ),
        ),
      ],
    );
  }

  // ── Passaggio 2: foto e luogo ──────────────────────────────────────────────

  Widget _intestazioneScheda(IconData icona, Accento accento, String titolo, Widget etichetta) => Row(
        children: [
          IconaTonda(icona, colore: accento.forte, sfondo: accento.tinta, dimensione: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(titolo, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: testo))),
          const SizedBox(width: 8),
          etichetta,
        ],
      );

  /// Riquadro grande e toccabile per scegliere la foto: icona sopra, testo sotto
  /// su una sola riga (si rimpicciolisce invece di andare a capo).
  Widget _opzioneFoto(IconData icona, String etichetta, VoidCallback onTap, {bool principale = false}) {
    final colore = principale ? Colors.white : cieloScuro;
    return Semantics(
      button: true,
      label: etichetta,
      excludeSemantics: true,
      child: Material(
        color: principale ? cieloScuro : cieloChiaro,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icona, size: 32, color: colore),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  etichetta,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colore),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _schedaPosizione(Copie s) {
    final trovata = _posizione != null;
    return Scheda(
      padding: const EdgeInsets.all(16),
      coloreBordo: trovata ? foglia.withValues(alpha: .5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _intestazioneScheda(
          trovata ? Icons.where_to_vote_rounded : Icons.location_on_rounded,
          trovata ? Accento.verde : Accento.arancio,
          s.t('Dove si trova?', 'Where is it?'),
          trovata
              ? Etichetta(s.t('Trovata', 'Found'), icona: Icons.check_rounded)
              : _caricamentoGps
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Etichetta(s.t('Necessaria', 'Required'), colore: coralloScuro, sfondo: coralloChiaro),
        ),
        const SizedBox(height: 10),
        Text(
          trovata
              ? s.t('Useremo il punto in cui ti trovi adesso.', 'We will use the spot where you are now.')
              : _caricamentoGps
                  ? s.t('Sto cercando la tua posizione…', 'Finding your location…')
                  : s.t('Mettiti vicino al problema e tocca il pulsante qui sotto.', 'Stand near the problem and tap the button below.'),
          style: TextStyle(fontSize: 14, height: 1.4, color: testoSecondario),
        ),
        AnimatedSize(
          duration: durata(context, 300),
          curve: Curves.easeOutCubic,
          child: trovata ? _mappaPosizione(s) : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Builder(builder: (context) {
            final onPressed = _caricamentoGps ? null : _rilevaPosizione;
            final icon = _caricamentoGps
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded);
            final label = Text(
              _caricamentoGps
                  ? s.t('Ricerca in corso…', 'Searching…')
                  : trovata
                      ? s.t('Aggiorna posizione', 'Update location')
                      : s.t('Trova la mia posizione', 'Find my location'),
            );
            // Pieno finché manca la posizione, poi secondario.
            return trovata
                ? OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label)
                : FilledButton.icon(onPressed: onPressed, icon: icon, label: label);
          }),
        ),
      ]),
    );
  }

  Widget _schedaFoto(Copie s) {
    return Scheda(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _intestazioneScheda(
          Icons.photo_camera_rounded,
          Accento.blu,
          s.t('Aggiungi una foto', 'Add a photo'),
          Etichetta(s.t('Facoltativa', 'Optional'), colore: testoSecondario, sfondo: sfondo),
        ),
        const SizedBox(height: 6),
        Text(
          s.t('Aiuta a capire subito il problema. Inquadra solo quello, senza persone né targhe.',
              'It helps show the problem at a glance. Frame only the problem, without people or number plates.'),
          style: TextStyle(fontSize: 14, height: 1.4, color: testoSecondario),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: durata(context, 250),
          child: _foto != null
              ? Column(
                  key: const ValueKey('foto'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FutureBuilder<Uint8List>(
                        future: _anteprimaFoto,
                        builder: (context, snapshot) => snapshot.hasData
                            ? Image.memory(
                                snapshot.data!,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                semanticLabel: s.t('Foto allegata', 'Attached photo'),
                              )
                            : Container(
                                height: 200,
                                color: sfondo,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selezionaFoto(ImageSource.camera),
                          icon: const Icon(Icons.refresh_rounded),
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.t('Cambia', 'Change'), maxLines: 1)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _rimuoviFoto,
                          style: OutlinedButton.styleFrom(foregroundColor: coralloScuro),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.t('Rimuovi', 'Remove'), maxLines: 1)),
                        ),
                      ),
                    ]),
                  ],
                )
              : Row(
                  key: const ValueKey('vuoto'),
                  children: [
                    Expanded(
                      child: _opzioneFoto(
                        Icons.photo_camera_rounded,
                        s.t('Scatta foto', 'Take photo'),
                        () => _selezionaFoto(ImageSource.camera),
                        principale: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _opzioneFoto(
                        Icons.photo_library_rounded,
                        s.t('Dalla galleria', 'From gallery'),
                        () => _selezionaFoto(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _passaggioFotoLuogo(Copie s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intestazionePassaggio(
          s.t('Dove si trova il problema?', 'Where is the problem?'),
          s.t('La posizione serve per trovarlo. La foto è facoltativa.', 'The location helps find it. The photo is optional.'),
        ),
        _schedaPosizione(s),
        const SizedBox(height: 14),
        _schedaFoto(s),
      ],
    );
  }

  Widget _mappaPosizione(Copie s) {
    final demo = CitizenApi.instance.demoMode;
    final punto = LatLng(_posizione!.latitude, _posizione!.longitude);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MappaParco(
          key: ValueKey(_rilevamenti),
          centro: punto,
          zoom: 17,
          altezza: 190,
          interattiva: demo,
          // In demo il punto si può spostare toccando la mappa.
          onTocco: demo ? (p) => setState(() => _posizione = _posizioneDa(p.latitude, p.longitude)) : null,
          marcatori: [
            Marker(
              point: punto,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(
                Icons.location_on_rounded,
                size: 44,
                color: corallo,
                shadows: [Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
            ),
          ],
        ),
        if (demo) ...[
          const SizedBox(height: 8),
          Text(
            s.t('Demo: tocca la mappa per spostare il punto.', 'Demo: tap the map to move the pin.'),
            style: TextStyle(fontSize: 12.5, color: testoSecondario),
          ),
        ],
      ]),
    );
  }

  // ── Passaggio 3: riepilogo ─────────────────────────────────────────────────

  Widget _rigaRiepilogo(String titolo, String valore, IconData icona, [Accento accento = Accento.verde]) {
    return Row(
      children: [
        IconaTonda(icona, colore: accento.forte, sfondo: accento.tinta, dimensione: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(titolo, style: TextStyle(fontSize: 14, color: testoSecondario)),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Text(
            valore,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testo),
          ),
        ),
      ],
    );
  }

  Widget _passaggioRiepilogo(Copie s) {
    final categoria = _categorie.firstWhere(
      (element) => element.id == _categoria,
      orElse: () => _categorieBase.last,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intestazionePassaggio(
          s.t('Ci siamo quasi!', 'Almost done!'),
          s.t('Se vuoi, aggiungi due parole. Poi tocca «Invia segnalazione».', 'Add a few words if you like, then tap “Send report”.'),
        ),
        _etichettaCampo(
          s.t('Quanto è urgente?', 'How urgent is it?'),
          s.t('Se non sei sicuro, lascia «Media».', 'If unsure, leave “Medium”.'),
        ),
        _selettoreGravita(s),
        const SizedBox(height: 20),
        _etichettaCampo(s.t('Vuoi aggiungere qualcosa? (facoltativo)', 'Anything to add? (optional)')),
        TextField(
          controller: _descrizione,
          minLines: 4,
          maxLines: 7,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: s.t(
              'Es. «Panchina rotta vicino alla fontana»',
              'E.g. “Broken bench near the fountain”',
            ),
            alignLabelWithHint: true,
            helperText: s.t('Non inserire dati personali.', 'Do not include personal information.'),
          ),
        ),
        const SizedBox(height: 14),
        Scheda(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('La tua segnalazione', 'Your report'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo)),
              const SizedBox(height: 14),
              _rigaRiepilogo(s.t('Categoria', 'Category'), s.t(categoria.nomeIt, categoria.nomeEn), categoria.icona, categoria.accento),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Urgenza', 'Urgency'),
                s.t(
                  _gravita == 'bassa' ? 'Bassa' : _gravita == 'media' ? 'Media' : 'Alta',
                  _gravita == 'bassa' ? 'Low' : _gravita == 'media' ? 'Medium' : 'High',
                ),
                Icons.flag_outlined,
                _gravita == 'alta' ? Accento.arancio : _gravita == 'media' ? Accento.giallo : Accento.verde,
              ),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Foto', 'Photo'),
                _foto != null ? s.t('Allegata', 'Attached') : s.t('Nessuna', 'None'),
                Icons.photo_outlined,
                Accento.blu,
              ),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Posizione', 'Location'),
                _posizione == null ? s.t('Mancante', 'Missing') : s.t('Trovata', 'Found'),
                Icons.location_on_outlined,
                _posizione == null ? Accento.arancio : Accento.verde,
              ),
              if (_descrizione.text.trim().isNotEmpty) ...[
                const Divider(height: 22),
                Text(s.t('Descrizione', 'Description'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testoSecondario)),
                const SizedBox(height: 5),
                Text(_descrizione.text.trim(), style: TextStyle(fontSize: 15, height: 1.45, color: testo)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pulsanti(Copie s) {
    return LayoutBuilder(
      builder: (context, vincoli) {
        final testoIngrandito = MediaQuery.textScalerOf(context).scale(16) > 18;
        final impilaPulsanti = _passaggio > 0 && (vincoli.maxWidth < 340 || testoIngrandito);
        final pulsanteIndietro = SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _tornaIndietro,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(s.t('Indietro', 'Back')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 56),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: superficie,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        );
        final pulsanteAvanti = SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _invioInCorso ? null : _vaiAvanti,
            icon: _invioInCorso
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_passaggio == 2 ? Icons.send_rounded : Icons.arrow_forward_rounded),
            label: Text(
              s.t(
                _invioInCorso ? 'Invio…' : _passaggio == 2 ? 'Invia segnalazione' : 'Continua',
                _invioInCorso ? 'Sending…' : _passaggio == 2 ? 'Send report' : 'Continue',
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: foresta,
              foregroundColor: Colors.white,
              disabledBackgroundColor: foresta.withValues(alpha: .6),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(0, 56),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        );

        if (_passaggio == 0) return SizedBox(width: double.infinity, child: pulsanteAvanti);
        if (impilaPulsanti) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pulsanteIndietro, const SizedBox(height: 10), pulsanteAvanti],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: pulsanteIndietro),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: pulsanteAvanti),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final animazioni = !MediaQuery.of(context).disableAnimations;

    return ContenitorePagina(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitoloPagina(
            key: _cima,
            titolo: s.t('Segnala un problema', 'Report a problem'),
            icona: Icons.add_a_photo_rounded,
            accento: Accento.arancio,
          ),
          Scheda(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: _indicatorePassaggi(s),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: durata(context, 340),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              // Il nuovo passaggio entra dal lato verso cui si va, il vecchio esce dall'altro.
              final entrante = child.key == ValueKey<int>(_passaggio);
              final verso = (entrante ? 1 : -1) * _versoPassaggio;
              return FadeTransition(
                opacity: animation,
                child: animazioni
                    ? SlideTransition(
                        position: Tween<Offset>(begin: Offset(.18 * verso, 0), end: Offset.zero).animate(animation),
                        child: child,
                      )
                    : child,
              );
            },
            layoutBuilder: (corrente, precedenti) => Stack(
              alignment: Alignment.topCenter,
              children: [...precedenti, ?corrente],
            ),
            child: KeyedSubtree(
              key: ValueKey<int>(_passaggio),
              child: _passaggio == 0
                  ? _passaggioProblema(s)
                  : _passaggio == 1
                      ? _passaggioFotoLuogo(s)
                      : _passaggioRiepilogo(s),
            ),
          ),
          AnimatedSize(
            duration: durata(context, 220),
            curve: Curves.easeOutCubic,
            child: _errore == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Riquadro(icona: Icons.error_outline_rounded, messaggio: _errore!, accento: Accento.arancio),
                    ),
                  ),
          ),
          const SizedBox(height: 22),
          _pulsanti(s),
        ],
      ),
    );
  }
}

class _CategoriaSegnalazione {
  final String id;
  final String nomeIt;
  final String nomeEn;
  final IconData icona;
  final Accento accento;

  const _CategoriaSegnalazione({
    required this.id,
    required this.nomeIt,
    required this.nomeEn,
    required this.icona,
    required this.accento,
  });

  // Icone Material indicate dal backend (campo `icon` di /citizen/categories).
  static const Map<String, IconData> _icone = {
    'lightbulb': Icons.lightbulb_outline_rounded,
    'delete': Icons.delete_outline_rounded,
    'park': Icons.park_outlined,
    'water_drop': Icons.water_drop_outlined,
    'water': Icons.water_outlined,
    'chair': Icons.chair_outlined,
    'cleaning_services': Icons.cleaning_services_outlined,
    'shield': Icons.shield_outlined,
    'sports_soccer': Icons.sports_soccer_outlined,
    'more_horiz': Icons.more_horiz_rounded,
  };

  static const Map<String, String> _nomiEn = {
    'lighting': 'Lighting',
    'waste': 'Bins and waste',
    'green': 'Trees and plants',
    'irrigation': 'Irrigation',
    'fountains': 'Drinking fountains',
    'furniture': 'Benches and furniture',
    'cleaning': 'Cleaning',
    'safety': 'Safety',
    'play': 'Playground and sports area',
    'other': 'Other',
  };

  /// Colore di ogni categoria nota; le altre ricevono un colore stabile dal codice.
  static const Map<String, Accento> _accenti = {
    'lighting': Accento.giallo,
    'waste': Accento.blu,
    'green': Accento.verde,
    'irrigation': Accento.blu,
    'fountains': Accento.blu,
    'furniture': Accento.arancio,
    'cleaning': Accento.viola,
    'safety': Accento.arancio,
    'play': Accento.giallo,
    'other': Accento.viola,
  };

  static const List<Accento> _ciclo = [Accento.verde, Accento.blu, Accento.giallo, Accento.arancio, Accento.viola];

  factory _CategoriaSegnalazione.fromBackend(Map<String, dynamic> json) {
    final code = json['code'] as String;
    final label = json['label'] as String? ?? code;
    return _CategoriaSegnalazione(
      id: code,
      nomeIt: label,
      nomeEn: _nomiEn[code] ?? label,
      icona: _icone[json['icon']] ?? Icons.label_outline_rounded,
      accento: _accenti[code] ?? _ciclo[code.codeUnits.fold<int>(0, (a, b) => a + b) % _ciclo.length],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segnalazione inviata
// ─────────────────────────────────────────────────────────────────────────────

/// Mostra la schermata di ringraziamento dopo l'invio. Restituisce `true` se
/// l'utente vuole vedere la segnalazione sulla mappa.
Future<bool?> mostraSegnalazioneInviata(
  BuildContext context, {
  required Copie s,
  required String codice,
  String? stato,
  bool conMappa = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      transitionDuration: durata(context, 420),
      reverseTransitionDuration: durata(context, 260),
      pageBuilder: (_, _, _) => SchermataInviata(s: s, codice: codice, stato: stato, conMappa: conMappa),
      transitionsBuilder: (_, a, _, figlio) {
        final curva = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curva,
          child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(curva), child: figlio),
        );
      },
    ),
  );
}

class SchermataInviata extends StatefulWidget {
  final Copie s;
  final String codice;
  final String? stato;
  final bool conMappa;
  const SchermataInviata({super.key, required this.s, required this.codice, this.stato, this.conMappa = true});

  @override
  State<SchermataInviata> createState() => _SchermataInviataState();
}

class _SchermataInviataState extends State<SchermataInviata> with TickerProviderStateMixin {
  /// Disegno del segno di spunta (cerchio, poi la spunta).
  late final AnimationController _spunta = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  /// Foglie che cadono, una volta sola.
  late final AnimationController _foglie = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  late final List<_Foglia> _elenco = _Foglia.genera(18);

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spunta.value = 1;
      _foglie.value = 1;
    } else if (!_spunta.isAnimating && _spunta.value == 0) {
      _spunta.forward();
      _foglie.forward();
    }
  }

  @override
  void dispose() {
    _spunta.dispose();
    _foglie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (fatto, _) {
        if (!fatto) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: sfondo,
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _foglie,
                  builder: (context, _) => CustomPaint(painter: _PittoreFoglie(_elenco, _foglie.value)),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Column(
                      children: [
                        const Spacer(),
                        Semantics(
                          label: s.t('Fatto', 'Done'),
                          child: SizedBox(
                            width: 132,
                            height: 132,
                            child: AnimatedBuilder(
                              animation: _spunta,
                              builder: (context, _) => CustomPaint(
                                painter: _PittoreSpunta(_spunta.value, foresta, menta),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        Appare(
                          indice: 2,
                          child: Text(
                            s.t('Segnalazione inviata', 'Report submitted'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: testo, letterSpacing: -.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Appare(
                          indice: 3,
                          child: Text(
                            s.t('Grazie! Il tuo aiuto rende il parco un posto migliore.',
                                'Thank you! Your help makes the park a better place.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15.5, height: 1.45, color: testoSecondario),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Appare(
                          indice: 4,
                          child: Scheda(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              children: [
                                IconaTonda(Icons.confirmation_number_rounded, colore: cieloScuro, sfondo: cieloChiaro, dimensione: 42),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.t('Numero segnalazione', 'Report number'),
                                          style: TextStyle(fontSize: 12.5, color: testoSecondario)),
                                      Text(
                                        widget.codice,
                                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: testo, letterSpacing: .3),
                                      ),
                                      if (widget.stato?.isNotEmpty ?? false)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Etichetta(widget.stato!, colore: cieloScuro, puntino: true),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: s.t('Copia il numero', 'Copy the number'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: widget.codice));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(s.t('Numero copiato.', 'Number copied.'))),
                                    );
                                  },
                                  icon: Icon(Icons.copy_rounded, color: testoSecondario),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Appare(
                          indice: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.conMappa) ...[
                                FilledButton.icon(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  icon: const Icon(Icons.map_rounded),
                                  label: Text(s.t('Vedi sulla mappa', 'See it on the map')),
                                ),
                                const SizedBox(height: 8),
                              ],
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: Text(s.t('Chiudi', 'Close')),
                              ),
                            ],
                          ),
                        ),
                      ],
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

/// Cerchio che si riempie e poi la spunta che si disegna.
class _PittoreSpunta extends CustomPainter {
  final double t;
  final Color colore;
  final Color tinta;
  _PittoreSpunta(this.t, this.colore, this.tinta);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final fondo = Curves.easeOutBack.transform((t / .45).clamp(0, 1));
    canvas.drawCircle(c, r * fondo, Paint()..color = tinta);
    final arco = Curves.easeInOut.transform((t / .55).clamp(0, 1));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 5),
      -math.pi / 2,
      2 * math.pi * arco,
      false,
      Paint()
        ..color = colore
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    final traccia = Curves.easeOut.transform(((t - .45) / .55).clamp(0, 1));
    if (traccia == 0) return;
    final percorso = Path()
      ..moveTo(c.dx - r * .34, c.dy + r * .02)
      ..lineTo(c.dx - r * .08, c.dy + r * .28)
      ..lineTo(c.dx + r * .38, c.dy - r * .24);
    final metrica = percorso.computeMetrics().first;
    canvas.drawPath(
      metrica.extractPath(0, metrica.length * traccia),
      Paint()
        ..color = colore
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PittoreSpunta old) => old.t != t || old.colore != colore;
}

class _Foglia {
  final double x, ritardo, velocita, oscillazione, giri, dimensione;
  final Color colore;
  const _Foglia(this.x, this.ritardo, this.velocita, this.oscillazione, this.giri, this.dimensione, this.colore);

  static List<_Foglia> genera(int quante) {
    final caso = math.Random(7);
    const colori = [Color(0xFF2FA36B), Color(0xFF17694A), Color(0xFFF0A202), Color(0xFF7CCB8F), Color(0xFFE4572E)];
    return [
      for (var i = 0; i < quante; i++)
        _Foglia(
          caso.nextDouble(),
          caso.nextDouble() * .35,
          .55 + caso.nextDouble() * .45,
          18 + caso.nextDouble() * 30,
          (caso.nextDouble() - .5) * 3,
          9 + caso.nextDouble() * 9,
          colori[i % colori.length],
        ),
    ];
  }
}

/// Foglie che scendono dall'alto oscillando e svaniscono.
class _PittoreFoglie extends CustomPainter {
  final List<_Foglia> foglie;
  final double t;
  _PittoreFoglie(this.foglie, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    for (final f in foglie) {
      final p = ((t - f.ritardo) / (1 - f.ritardo)).clamp(0.0, 1.0);
      if (p == 0) continue;
      final y = -30 + (size.height * .75) * p * f.velocita;
      final x = f.x * size.width + math.sin(p * math.pi * 3) * f.oscillazione;
      final alfa = p < .8 ? 1.0 : (1 - p) / .2;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(f.giri * math.pi * p);
      final d = f.dimensione;
      final foglia = Path()
        ..moveTo(0, -d)
        ..quadraticBezierTo(d * .75, 0, 0, d)
        ..quadraticBezierTo(-d * .75, 0, 0, -d);
      canvas.drawPath(foglia, Paint()..color = f.colore.withValues(alpha: .85 * alfa));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PittoreFoglie old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Idee
// ─────────────────────────────────────────────────────────────────────────────

/// Idea pubblicata nel parco: nel backend è una segnalazione `suggestion`.
/// La prima riga della descrizione fa da titolo.
class _IdeaItem {
  final int id;
  final String code;
  final String title;
  final String description;
  final String? categoryLabel;
  final String status;
  final String statusLabel;
  final bool mine;
  final DateTime createdAt;

  const _IdeaItem({required this.id, required this.code, required this.title, required this.description, required this.categoryLabel, required this.status, required this.statusLabel, required this.mine, required this.createdAt});

  factory _IdeaItem.fromJson(Map<String, dynamic> json) {
    final text = (json['description'] as String? ?? '').trim();
    final newline = text.indexOf('\n');
    return _IdeaItem(
      id: json['id'] as int,
      code: json['code'] as String? ?? '',
      title: newline < 0 ? text : text.substring(0, newline).trim(),
      description: newline < 0 ? '' : text.substring(newline + 1).trim(),
      categoryLabel: json['category_label'] as String?,
      status: json['status'] as String? ?? 'received',
      statusLabel: json['status_label'] as String? ?? '',
      mine: json['is_mine'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  String get dateLabel => formattaData(createdAt);
}

/// Scorre la pagina fino all'elemento con [chiave] (avviso o idea aperti da Parky).
void mostraInVista(GlobalKey chiave) {
  final ctx = chiave.currentContext;
  if (ctx == null) return;
  final animazioni = !MediaQuery.of(ctx).disableAnimations;
  Scrollable.ensureVisible(
    ctx,
    alignment: .15,
    duration: animazioni ? const Duration(milliseconds: 400) : Duration.zero,
    curve: Curves.easeOutCubic,
  );
}

class SchermataIdee extends StatefulWidget {
  final Copie s;
  /// Idea da mettere in evidenza (es. dalle fonti dell'assistente).
  final int? evidenzia;
  const SchermataIdee({super.key, required this.s, this.evidenzia});
  @override
  State<SchermataIdee> createState() => _SchermataIdeeState();
}

class _SchermataIdeeState extends State<SchermataIdee> {
  static const Map<String, dynamic> _categoriaPredefinita = {'code': 'other', 'label': 'Altro'};

  bool _caricamento = true;
  String? _errore;
  List<_IdeaItem> _idee = [];
  final GlobalKey _chiaveEvidenziata = GlobalKey();
  bool _evidenziataMostrata = false;
  List<Map<String, dynamic>> _categorie = const [_categoriaPredefinita];
  StreamSubscription<Map<String, dynamic>>? _live;
  Timer? _debounce;
  // Restano qui: se l'utente chiude il pannello, la bozza non va persa.
  final TextEditingController _titolo = TextEditingController();
  final TextEditingController _dettagli = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_caricaIdee());
    unawaited(_caricaCategorie());
    CitizenApi.instance.connectLive();
    _live = CitizenApi.instance.events.listen((e) {
      final type = e['type'];
      final data = e['data'];
      final suggerimento = data is Map && data['kind'] == 'suggestion';
      if ((type == 'report_created' && suggerimento) || type == 'report_status_changed') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () => _caricaIdee(silenzioso: true));
      }
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    _titolo.dispose();
    _dettagli.dispose();
    super.dispose();
  }

  Future<void> _caricaCategorie() async {
    try {
      final rows = await CitizenApi.instance.getCategories(kind: 'suggestion');
      if (mounted && rows.isNotEmpty) setState(() => _categorie = rows);
    } catch (_) {
      // Resta "Altro", accettata dal backend anche per i suggerimenti.
    }
  }

  Future<void> _caricaIdee({bool silenzioso = false}) async {
    if (!silenzioso && mounted) setState(() { _caricamento = true; _errore = null; });
    try {
      final result = await CitizenApi.instance.getFeed(kind: 'suggestion', limit: 50);
      final rows = (result['items'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _idee = rows.map(_IdeaItem.fromJson).toList(); _caricamento = false; _errore = null; });
      _mostraEvidenziata();
    } catch (e) {
      if (mounted) setState(() { _errore = e.toString(); _caricamento = false; });
    }
  }

  Future<void> _apriNuovaIdea() async {
    final s = widget.s;
    final pubblicata = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FoglioNuovaIdea(s: s, categorie: _categorie, titolo: _titolo, dettagli: _dettagli),
    );
    if (pubblicata == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('Idea pubblicata.', 'Idea published.'))));
      await _caricaIdee(silenzioso: true);
    }
  }

  /// Porta in vista l'idea indicata in [SchermataIdee.evidenzia], una volta sola.
  void _mostraEvidenziata() {
    if (widget.evidenzia == null || _evidenziataMostrata) return;
    _evidenziataMostrata = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => mostraInVista(_chiaveEvidenziata));
  }

  Widget _schedaIdea(_IdeaItem idea, Copie s) {
    final evidenziata = idea.id == widget.evidenzia;
    return Scheda(
      key: evidenziata ? _chiaveEvidenziata : null,
      padding: const EdgeInsets.all(16),
      colore: evidenziata ? soleChiaro : superficie,
      coloreBordo: evidenziata ? soleScuro : idea.mine ? sole.withValues(alpha: .45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconaTonda(Icons.lightbulb_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(idea.title, style: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w800, color: testo)),
            if (idea.description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(idea.description, style: TextStyle(fontSize: 14, height: 1.45, color: testoSecondario)),
            ],
          ])),
        ]),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_rounded, size: 15, color: testoTenue),
            const SizedBox(width: 5),
            Text([idea.dateLabel, if (idea.categoryLabel != null) idea.categoryLabel!].join(' · '), style: TextStyle(fontSize: 13, color: testoSecondario)),
          ]),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
            if (idea.mine) Etichetta(s.t('La tua idea', 'Your idea'), icona: Icons.person_rounded),
            if (idea.statusLabel.isNotEmpty) Etichetta(idea.statusLabel, colore: testoSecondario, sfondo: sfondo, puntino: true),
          ]),
        ]),
      ]),
    );
  }

  Widget _elencoIdee(Copie s) {
    if (_caricamento) {
      return CaricamentoScheletro(key: const ValueKey('caricamento'), numero: 2, etichetta: s.t('Caricamento delle idee', 'Loading ideas'));
    }
    if (_errore != null) {
      return StatoVuoto(
        key: const ValueKey('errore'),
        icona: Icons.cloud_off_rounded,
        messaggio: _errore!,
        accento: Accento.arancio,
        onAzione: _caricaIdee,
        etichettaAzione: s.t('Riprova', 'Retry'),
      );
    }
    if (_idee.isEmpty) {
      return StatoVuoto(
        key: const ValueKey('vuoto'),
        icona: Icons.emoji_objects_outlined,
        messaggio: s.t('Non ci sono ancora idee. Puoi essere il primo a proporne una.', 'There are no ideas yet. You can be the first to suggest one.'),
        accento: Accento.giallo,
        onAzione: _apriNuovaIdea,
        etichettaAzione: s.t('Proponi un’idea', 'Suggest an idea'),
      );
    }
    return Column(
      key: const ValueKey('elenco'),
      children: [
        for (final (i, idea) in _idee.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Appare(indice: i, child: _schedaIdea(idea, s)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return RefreshIndicator(
      onRefresh: () => _caricaIdee(silenzioso: true),
      child: ContenitorePagina(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TitoloPagina(
          titolo: s.t('Idee per il parco', 'Ideas for the park'),
          icona: Icons.lightbulb_rounded,
          accento: Accento.giallo,
        ),
        PulsanteAzione(
          testo: s.t('Proponi un’idea', 'Suggest an idea'),
          icona: Icons.add_rounded,
          colore: soleScuro,
          onPressed: _apriNuovaIdea,
        ),
        const SizedBox(height: 28),
        TitoloSezione(
          s.t('Idee della comunità', 'Community ideas'),
          dettaglio: '${_idee.length} ${s.t('idee', 'ideas')}',
          accento: Accento.giallo,
        ),
        AnimatedSwitcher(duration: durata(context, 250), child: _elencoIdee(s)),
      ])),
    );
  }
}

/// Pannello che si apre dal pulsante "Proponi un'idea".
/// Chiude restituendo `true` quando l'idea è stata pubblicata.
class _FoglioNuovaIdea extends StatefulWidget {
  final Copie s;
  final List<Map<String, dynamic>> categorie;
  final TextEditingController titolo;
  final TextEditingController dettagli;
  const _FoglioNuovaIdea({required this.s, required this.categorie, required this.titolo, required this.dettagli});

  @override
  State<_FoglioNuovaIdea> createState() => _FoglioNuovaIdeaState();
}

class _FoglioNuovaIdeaState extends State<_FoglioNuovaIdea> {
  bool _invio = false;
  late String _categoria = widget.categorie.any((c) => c['code'] == 'other')
      ? 'other'
      : (widget.categorie.first['code'] as String);

  String _nomeCategoria(String code) =>
      (widget.categorie.firstWhere((c) => c['code'] == code, orElse: () => const {'label': 'Altro'})['label'] ?? code).toString();

  Future<void> _mostraAnteprima() async {
    final s = widget.s;
    final titolo = widget.titolo.text.trim();
    final dettagli = widget.dettagli.text.trim();
    if (titolo.length < 3 || dettagli.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('Inserisci un titolo di almeno 3 caratteri e una descrizione di almeno 10.', 'Enter a title of at least 3 characters and a description of at least 10.'))));
      return;
    }
    final conferma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: IconaTonda(Icons.lightbulb_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 56),
        title: Text(s.t('Anteprima del suggerimento', 'Suggestion preview')),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: sfondo, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titolo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.3)),
              const SizedBox(height: 6),
              Text(dettagli, style: TextStyle(color: testoSecondario, height: 1.4)),
              const SizedBox(height: 10),
              Etichetta('${s.t('Argomento', 'Topic')}: ${_nomeCategoria(_categoria)}', colore: soleScuro, sfondo: soleChiaro),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.public_rounded, size: 16, color: testoSecondario),
            const SizedBox(width: 6),
            Expanded(child: Text(s.t('Sarà visibile a tutti gli utenti dell’app.', 'It will be visible to all app users.'), style: TextStyle(color: testoSecondario, fontSize: 13))),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s.t('Modifica', 'Edit'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(s.t('Invia idea', 'Submit idea'))),
        ],
      ),
    );
    if (conferma == true) await _inviaIdea();
  }

  Future<void> _inviaIdea() async {
    final titolo = widget.titolo.text.trim();
    final dettagli = widget.dettagli.text.trim();
    setState(() => _invio = true);
    try {
      // Il backend non ha un titolo: va nella prima riga della descrizione (max 1000 caratteri).
      await CitizenApi.instance.createSuggestion(category: _categoria, description: '$titolo\n$dettagli');
      widget.titolo.clear();
      widget.dettagli.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _invio = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconaTonda(Icons.edit_note_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('La tua idea', 'Your idea'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: testo)),
                const SizedBox(height: 3),
                Text(s.t('Raccontaci cosa migliorerebbe il parco.', 'Tell us what could make the park better.'), style: TextStyle(fontSize: 14, height: 1.4, color: testoSecondario)),
              ])),
            ]),
            const SizedBox(height: 18),
            TextField(controller: widget.titolo, autofocus: true, textCapitalization: TextCapitalization.sentences, maxLength: 120, decoration: InputDecoration(labelText: s.t('Titolo', 'Title'), hintText: s.t('Es. Più ombra vicino all’area giochi', 'E.g. More shade near the playground'))),
            const SizedBox(height: 10),
            TextField(controller: widget.dettagli, minLines: 3, maxLines: 4, maxLength: 870, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: s.t('Descrizione', 'Description'), hintText: s.t('Descrivi la tua idea in poche parole…', 'Describe your idea in a few words…'), helperText: s.t('Non inserire dati personali.', 'Do not include personal information.'), alignLabelWithHint: true)),
            const SizedBox(height: 14),
            Text(s.t('Argomento', 'Topic'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: testo)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in widget.categorie)
                ChoiceChip(
                  label: Text((c['label'] ?? c['code']).toString()),
                  selected: _categoria == c['code'],
                  showCheckmark: false,
                  selectedColor: soleChiaro,
                  side: BorderSide(color: _categoria == c['code'] ? sole : bordo, width: _categoria == c['code'] ? 1.5 : 1),
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _categoria == c['code'] ? soleScuro : testo),
                  onSelected: (_) => setState(() => _categoria = c['code'] as String),
                ),
            ]),
            const SizedBox(height: 16),
            Riquadro(
              icona: Icons.public_rounded,
              accento: Accento.blu,
              messaggio: s.t('Le idee sono pubbliche: le vedono tutti gli utenti dell’app e i gestori del parco.', 'Ideas are public: all app users and park managers can see them.'),
            ),
            const SizedBox(height: 16),
            PulsanteAzione(testo: _invio ? s.t('Invio in corso...', 'Submitting...') : s.t('Rivedi e invia', 'Review and submit'), icona: Icons.send_rounded, onPressed: _invio ? null : _mostraAnteprima),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avvisi
// ─────────────────────────────────────────────────────────────────────────────

class Avviso {
  final int? id;
  final String categoria;
  final String? statoManutenzione;
  final IconData icona;
  final Color colore;
  final String titoloIt;
  final String titoloEn;
  final String descrizioneIt;
  final String descrizioneEn;
  final String data;
  /// Inizio dell'avviso, per la data relativa («ieri», «3 giorni fa»).
  final DateTime? quando;

  const Avviso({
    this.id,
    required this.categoria,
    this.statoManutenzione,
    required this.icona,
    required this.colore,
    required this.titoloIt,
    required this.titoloEn,
    required this.descrizioneIt,
    required this.descrizioneEn,
    required this.data,
    this.quando,
  });
}

class SchermataAvvisi extends StatefulWidget {
  final Copie s;
  /// Cambia ogni volta che l'utente apre la scheda: gli avvisi si ricaricano.
  final int aperture;
  /// Avviso da mettere in evidenza (es. dalle fonti dell'assistente).
  final int? evidenzia;
  const SchermataAvvisi({super.key, required this.s, this.aperture = 0, this.evidenzia});

  @override
  State<SchermataAvvisi> createState() => _SchermataAvvisiState();
}

class _SchermataAvvisiState extends State<SchermataAvvisi> {
  String _filtro = 'tutti';
  List<Avviso> _avvisi = [];
  final GlobalKey _chiaveEvidenziata = GlobalKey();
  bool _evidenziataMostrata = false;
  bool _caricamento = true;
  String? _errore;
  StreamSubscription<Map<String, dynamic>>? _live;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_caricaAvvisi());
    CitizenApi.instance.connectLive();
    // Il backend avvisa quando compare un avviso o cambia lo stato del parco;
    // per modifiche e cancellazioni non c'è evento: ci pensano apertura e pull-to-refresh.
    _live = CitizenApi.instance.events.listen((e) {
      final type = e['type'];
      if (type == 'notice_created' || type == 'notice_ended' || type == 'park_status_changed') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () => _caricaAvvisi(silenzioso: true));
      }
    });
  }

  @override
  void didUpdateWidget(SchermataAvvisi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aperture != widget.aperture) unawaited(_caricaAvvisi(silenzioso: true));
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _caricaAvvisi({bool silenzioso = false}) async {
    if (!silenzioso && mounted) setState(() { _caricamento = true; _errore = null; });
    try {
      final rows = await CitizenApi.instance.getNotices();
      final parsed = rows.map((item) {
        final level = item['level'] as String? ?? 'info';
        final category = level == 'alert' ? 'importante' : level == 'warning' ? 'manutenzione' : 'novita';
        return Avviso(
          id: (item['id'] as num?)?.toInt(),
          categoria: category,
          icona: level == 'alert' ? Icons.priority_high_rounded : level == 'warning' ? Icons.handyman_rounded : Icons.new_releases_rounded,
          colore: level == 'alert' ? coralloScuro : level == 'warning' ? soleScuro : cieloScuro,
          titoloIt: item['title'] as String? ?? '',
          titoloEn: item['title'] as String? ?? '',
          descrizioneIt: item['body'] as String? ?? '',
          descrizioneEn: item['body'] as String? ?? '',
          data: formattaData(item['starts_at']),
          quando: DateTime.tryParse(item['starts_at']?.toString() ?? '')?.toLocal(),
        );
      }).toList();
      if (mounted) setState(() { _avvisi = parsed; _caricamento = false; _errore = null; });
      if (widget.evidenzia != null && !_evidenziataMostrata) {
        _evidenziataMostrata = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => mostraInVista(_chiaveEvidenziata));
      }
    } catch (e) {
      // Un aggiornamento silenzioso fallito non cancella gli avvisi già mostrati.
      if (mounted && (!silenzioso || _avvisi.isEmpty)) setState(() { _errore = e.toString(); _caricamento = false; });
    }
  }

  Widget _filtroAvvisi(String valore, String etichetta, IconData icona, Accento accento) {
    final selezionato = _filtro == valore;
    return ChoiceChip(
      avatar: Icon(icona, size: 18, color: selezionato ? accento.forte : testoSecondario),
      label: Text(etichetta),
      selected: selezionato,
      showCheckmark: false,
      selectedColor: accento.tinta,
      backgroundColor: superficie,
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: selezionato ? accento.forte : testo),
      side: BorderSide(color: selezionato ? accento.base : bordo, width: selezionato ? 1.5 : 1),
      onSelected: (_) => setState(() => _filtro = valore),
    );
  }

  Widget _schedaAvviso(Avviso avviso, Copie s) {
    final importante = avviso.categoria == 'importante';
    final evidenziato = avviso.id != null && avviso.id == widget.evidenzia;
    final quando = avviso.quando == null ? avviso.data : dataRelativa(avviso.quando!, s);
    final descrizione = s.t(avviso.descrizioneIt, avviso.descrizioneEn);
    return Scheda(
      key: evidenziato ? _chiaveEvidenziata : null,
      padding: EdgeInsets.zero,
      colore: evidenziato
          ? cieloChiaro
          : importante
              ? (temaScuro ? Color.alphaBlend(corallo.withValues(alpha: .08), superficie) : const Color(0xFFFFF7F5))
              : superficie,
      coloreBordo: evidenziato ? cieloScuro : importante ? corallo.withValues(alpha: .40) : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Striscia del colore della categoria: si riconosce il tipo a colpo d'occhio.
            Container(width: importante ? 5 : 4, color: avviso.colore.withValues(alpha: importante ? 1 : .7)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconaTonda(avviso.icona, colore: avviso.colore, dimensione: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: _etichettaCategoria(s, avviso.categoria, avviso.statoManutenzione),
                                style: TextStyle(fontWeight: FontWeight.w800, color: avviso.colore),
                              ),
                              if (quando.isNotEmpty)
                                TextSpan(text: '  ·  $quando', style: TextStyle(color: testoSecondario)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (importante) Etichetta(s.t('DA LEGGERE', 'PLEASE READ'), colore: coralloScuro, sfondo: coralloChiaro),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.t(avviso.titoloIt, avviso.titoloEn),
                      style: TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w800, color: testo),
                    ),
                    if (descrizione.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(descrizione, style: TextStyle(fontSize: 14.5, height: 1.5, color: testoSecondario)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final elenco = _avvisi
        .where((avviso) => _filtro == 'tutti' || avviso.categoria == _filtro)
        .toList();
    if (_filtro == 'tutti') {
      elenco.sort(
        (a, b) => (b.categoria == 'importante' ? 1 : 0).compareTo(
          a.categoria == 'importante' ? 1 : 0,
        ),
      );
    }

    final Widget contenuto;
    if (_caricamento) {
      contenuto = CaricamentoScheletro(key: const ValueKey('caricamento'), etichetta: s.t('Caricamento degli avvisi', 'Loading notices'));
    } else if (_errore != null) {
      contenuto = StatoVuoto(
        key: const ValueKey('errore'),
        icona: Icons.cloud_off_rounded,
        messaggio: _errore!,
        accento: Accento.arancio,
        onAzione: _caricaAvvisi,
        etichettaAzione: s.t('Riprova', 'Retry'),
      );
    } else if (elenco.isEmpty) {
      contenuto = StatoVuoto(
        key: ValueKey('vuoto-$_filtro'),
        icona: Icons.notifications_off_outlined,
        messaggio: s.t('Non ci sono aggiornamenti in questa categoria.', 'There are no updates in this category.'),
        accento: Accento.viola,
      );
    } else {
      contenuto = Column(
        key: ValueKey('elenco-$_filtro'),
        children: [
          for (final (i, avviso) in elenco.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Appare(indice: i, child: _schedaAvviso(avviso, s)),
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _caricaAvvisi(silenzioso: true),
      child: ContenitorePagina(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitoloPagina(
              titolo: s.t('Avvisi del parco', 'Park notices'),
              icona: Icons.notifications_rounded,
              accento: Accento.viola,
            ),
            // Filtri su una sola riga che scorre di lato.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final (i, f) in [
                    ('tutti', s.t('Tutti', 'All'), Icons.apps_rounded, Accento.viola),
                    ('importante', s.t('Importanti', 'Important'), Icons.priority_high_rounded, Accento.arancio),
                    ('manutenzione', s.t('Manutenzione', 'Maintenance'), Icons.handyman_rounded, Accento.giallo),
                    ('novita', s.t('Novità', 'News'), Icons.new_releases_rounded, Accento.blu),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _filtroAvvisi(f.$1, f.$2, f.$3, f.$4),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!_caricamento && _errore == null)
              TitoloSezione(
                s.t('Aggiornamenti', 'Updates'),
                dettaglio: '${elenco.length} ${s.t('elementi', 'items')}',
                accento: Accento.viola,
              ),
            AnimatedSwitcher(duration: durata(context, 250), child: contenuto),
          ],
        ),
      ),
    );
  }
}

String _etichettaCategoria(
  Copie s,
  String categoria,
  String? statoManutenzione,
) {
  switch (categoria) {
    case 'importante':
      return s.t('Avviso importante', 'Important notice');
    case 'novita':
      return s.t('Novità', 'News');
    case 'manutenzione':
      switch (statoManutenzione) {
        case 'segnalata':
          return s.t('Manutenzione segnalata', 'Maintenance reported');
        case 'in_corso':
          return s.t('Manutenzione in corso', 'Maintenance in progress');
        case 'completata':
          return s.t('Manutenzione completata', 'Maintenance completed');
      }
      return s.t('Manutenzione', 'Maintenance');
    default:
      return s.t('Aggiornamento', 'Update');
  }
}
