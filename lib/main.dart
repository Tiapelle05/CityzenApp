import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'citizen_api.dart';
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

class _ParkAppState extends State<ParkApp> {
  bool _inglese = false;
  /// Falso finché l'utente non ha scelto un server o la demo: si mostra la pagina di accesso.
  bool _collegato = CitizenApi.instance.configurato;
  /// Cresce a ogni nuovo collegamento: tutte le schermate ricaricano i dati.
  int _sessione = 0;
  final ThemeData _tema = temaTryees();

  @override
  Widget build(BuildContext context) {
    void cambiaLingua(bool valore) => setState(() => _inglese = valore);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Treeyes_Cityzen',
      theme: _tema,
      home: _collegato
          ? NavigazionePrincipale(
              key: ValueKey(_sessione),
              inglese: _inglese,
              onLinguaCambiata: cambiaLingua,
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
  final bool demo;
  /// Torna alla pagina di accesso per scegliere un altro server o la demo.
  final VoidCallback? onCambiaCollegamento;
  /// Chiamata dopo il passaggio diretto demo ⇄ server: l'app ricarica le schermate.
  final VoidCallback? onProfiloCambiato;

  const NavigazionePrincipale({
    super.key,
    required this.inglese,
    required this.onLinguaCambiata,
    this.demo = false,
    this.onCambiaCollegamento,
    this.onProfiloCambiato,
  });

  @override
  State<NavigazionePrincipale> createState() => _NavigazionePrincipaleState();
}

class _NavigazionePrincipaleState extends State<NavigazionePrincipale>
    with SingleTickerProviderStateMixin {
  /// Colore di ogni sezione, nello stesso ordine delle pagine.
  static const List<Accento> _accenti = [
    Accento.verde,
    Accento.blu,
    Accento.arancio,
    Accento.giallo,
    Accento.viola,
  ];

  int _pagina = 0;
  /// Cresce a ogni segnalazione inviata: la mappa si ricarica.
  int _invii = 0;
  /// Cresce a ogni apertura della scheda Avvisi: la lista si ricarica.
  int _apertureAvvisi = 0;
  late final AnimationController _transizione = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  StreamSubscription<Map<String, dynamic>>? _live;
  /// Avvisi di pericolo già mostrati: lo stesso avviso non riapre la finestra.
  final Set<Object> _pericoliMostrati = {};
  bool _cambioProfilo = false;

  @override
  void initState() {
    super.initState();
    // Collegamento live attivo in tutta l'app, non solo nelle schede che lo usano:
    // un pericolo segnalato dal backend deve arrivare ovunque si trovi l'utente.
    CitizenApi.instance.connectLive();
    _live = CitizenApi.instance.events.listen((e) {
      final dati = e['data'];
      if (dati is! Map) return;
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

  @override
  void dispose() {
    _live?.cancel();
    _transizione.dispose();
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
          side: const BorderSide(color: coralloScuro, width: 2),
        ),
        icon: const IconaTonda(Icons.warning_amber_rounded, colore: coralloScuro, sfondo: coralloChiaro, dimensione: 64),
        title: Semantics(
          liveRegion: true,
          child: Text(
            titolo == null || titolo.isEmpty ? s.t('Pericolo nel parco', 'Danger in the park') : titolo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: coralloScuro),
          ),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: coralloChiaro, borderRadius: BorderRadius.circular(12)),
            child: Text(
              s.t('AVVISO DI SICUREZZA', 'SAFETY ALERT'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: coralloScuro, letterSpacing: .8),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            testoAvviso == null || testoAvviso.isEmpty
                ? s.t('Evita la zona e segui le indicazioni del personale.', 'Avoid the area and follow staff instructions.')
                : testoAvviso,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.4, color: testo),
          ),
          const SizedBox(height: 10),
          Text(
            s.t('In caso di emergenza chiama il 112.', 'In an emergency call 112.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testoSecondario),
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
    if (vediAvvisi == true && mounted) _vaiA(4);
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
    if (indice != _pagina) {
      setState(() => _pagina = indice);
      if (!MediaQuery.of(context).disableAnimations) _transizione.forward(from: 0);
    }
    if (indice == 4) setState(() => _apertureAvvisi++);
  }

  Widget _selettoreLingua(Copie s) {
    return PopupMenuButton<bool>(
      tooltip: s.t('Cambia lingua', 'Change language'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.under,
      onSelected: widget.onLinguaCambiata,
      itemBuilder: (context) => [
        CheckedPopupMenuItem<bool>(
          value: false,
          checked: !widget.inglese,
          child: const Row(children: [Text('🇮🇹'), SizedBox(width: 10), Text('Italiano')]),
        ),
        CheckedPopupMenuItem<bool>(
          value: true,
          checked: widget.inglese,
          child: const Row(children: [Text('🇬🇧'), SizedBox(width: 10), Text('English')]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: superficie,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: bordo),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate_rounded, size: 17, color: foresta),
            const SizedBox(width: 5),
            Text(
              widget.inglese ? 'EN' : 'IT',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: testo, letterSpacing: .4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apriCollegamento(Copie s) async {
    final demo = widget.demo;
    final server = CitizenApi.instance.baseUrl;
    final cambia = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconaTonda(
                  demo ? Icons.science_rounded : Icons.cloud_done_rounded,
                  colore: demo ? lavanda : foresta,
                  sfondo: demo ? lavandaChiaro : menta,
                  dimensione: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      demo ? s.t('Modalità demo', 'Demo mode') : s.t('Collegato al server', 'Connected to the server'),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      demo ? s.t('Dati simulati, nulla viene inviato.', 'Simulated data, nothing is sent.') : server,
                      style: const TextStyle(fontSize: 14, color: testoSecondario),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(demo ? s.t('Collegati a un server', 'Connect to a server') : s.t('Cambia server o usa la demo', 'Change server or use demo')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (cambia == true) {
      CitizenApi.instance.disconnectLive();
      widget.onCambiaCollegamento?.call();
    }
  }

  /// Interruttore a due segmenti Demo | Server sempre visibile nella barra in alto.
  /// Toccare il profilo non attivo lo attiva subito; toccare quello attivo apre
  /// i dettagli del collegamento (per cambiare server).
  Widget _pulsanteCollegamento(Copie s) {
    Widget segmento({required bool demo, required IconData icona, required String etichetta}) {
      final attivo = widget.demo == demo;
      final colore = demo ? lavanda : foresta;
      return Semantics(
        button: true,
        selected: attivo,
        label: etichetta,
        child: Tooltip(
          message: attivo
              ? s.t('Dettagli collegamento', 'Connection details')
              : s.t('Passa a: $etichetta', 'Switch to: $etichetta'),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _cambioProfilo ? null : () => attivo ? _apriCollegamento(s) : _cambiaProfilo(demo),
            child: AnimatedContainer(
              duration: durata(context, 200),
              constraints: const BoxConstraints(minHeight: 32, minWidth: 36),
              padding: EdgeInsets.symmetric(horizontal: attivo ? 10 : 8, vertical: 6),
              decoration: BoxDecoration(
                color: attivo ? (demo ? lavandaChiaro : menta) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_cambioProfilo && !attivo)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colore))
                else
                  Icon(icona, size: 17, color: attivo ? colore : testoTenue),
                if (attivo) ...[
                  const SizedBox(width: 5),
                  Text(
                    etichetta.toUpperCase(),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: colore, letterSpacing: .5),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: superficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bordo),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        segmento(demo: true, icona: Icons.science_rounded, etichetta: 'Demo'),
        segmento(demo: false, icona: Icons.cloud_done_outlined, etichetta: 'Server'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Copie(widget.inglese);
    final accento = _accenti[_pagina];
    final pagine = [
      SchermataInizio(
        key: ValueKey('inizio-$_invii'),
        s: s,
        onSegnalazioni: () => _vaiA(2),
        onMappa: () => _vaiA(1),
        onIdee: () => _vaiA(3),
        onAvvisi: () => _vaiA(4),
      ),
      SchermataSegnalazioni(key: ValueKey('mappa-$_invii'), s: s),
      SchermataSegnalazione(
        s: s,
        onInviata: () {
          // La mappa si ricarica e mostra subito la nuova segnalazione.
          setState(() => _invii++);
          _vaiA(1);
        },
      ),
      SchermataIdee(s: s),
      SchermataAvvisi(s: s, aperture: _apertureAvvisi),
    ];
    final curva = CurvedAnimation(parent: _transizione, curve: Curves.easeOutCubic);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        toolbarHeight: 64,
        // Marchio su due righe (Treeyes / CITYZEN) che si rimpicciolisce invece di
        // troncarsi: così resta leggibile accanto a Demo|Server e alla lingua.
        title: Row(
          children: [
            Image.asset('Assets/logo_treeyes.png', height: 38, semanticLabel: 'Treeyes_Cityzen'),
            const SizedBox(width: 9),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Treeyes',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: forestaScura,
                        letterSpacing: -.4,
                      ),
                    ),
                    Text(
                      'CITYZEN',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: foresta,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.onCambiaCollegamento != null) ...[
            _pulsanteCollegamento(s),
            const SizedBox(width: 8),
          ],
          _selettoreLingua(s),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: curva,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(curva),
            child: IndexedStack(index: _pagina, children: pagine),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: superficie,
          border: Border(top: BorderSide(color: bordo)),
          boxShadow: [BoxShadow(color: Color(0x0F12261B), blurRadius: 20, offset: Offset(0, -4))],
        ),
        child: NavigationBarTheme(
          // L'indicatore prende il colore della sezione aperta.
          data: NavigationBarTheme.of(context).copyWith(
            indicatorColor: accento.tinta,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (stati) => TextStyle(
                fontSize: 12,
                fontWeight: stati.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
                color: stati.contains(WidgetState.selected) ? accento.forte : testoSecondario,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (stati) => IconThemeData(
                size: 24,
                color: stati.contains(WidgetState.selected) ? accento.forte : testoSecondario,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _pagina,
            onDestinationSelected: _vaiA,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: s.t('Inizio', 'Home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.map_outlined),
                selectedIcon: const Icon(Icons.map_rounded),
                label: s.t('Mappa', 'Map'),
              ),
              NavigationDestination(
                // Azione principale: sempre ben riconoscibile, al centro.
                icon: Container(
                  width: 44,
                  height: 32,
                  decoration: BoxDecoration(color: corallo, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                ),
                label: s.t('Segnala', 'Report'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.lightbulb_outline_rounded),
                selectedIcon: const Icon(Icons.lightbulb_rounded),
                label: s.t('Idee', 'Ideas'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.notifications_none_rounded),
                selectedIcon: const Icon(Icons.notifications_rounded),
                label: s.t('Avvisi', 'Notices'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inizio
// ─────────────────────────────────────────────────────────────────────────────

class SchermataInizio extends StatefulWidget {
  final Copie s;
  final VoidCallback onSegnalazioni;
  final VoidCallback? onMappa;
  final VoidCallback? onIdee;
  final VoidCallback? onAvvisi;

  const SchermataInizio({
    super.key,
    required this.s,
    required this.onSegnalazioni,
    this.onMappa,
    this.onIdee,
    this.onAvvisi,
  });

  @override
  State<SchermataInizio> createState() => _SchermataInizioState();
}

class _SchermataInizioState extends State<SchermataInizio> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;

    return ContenitorePagina(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Appare(
            child: TitoloPagina(
              titolo: s.t('Esplora il parco', 'Explore the park'),
            ),
          ),
          Appare(indice: 1, child: AnteprimaMappa(s: s, onApri: widget.onMappa)),
          const SizedBox(height: 18),
          Appare(
            indice: 2,
            child: _TesseraAzione(
              icona: Icons.add_location_alt_rounded,
              titolo: s.t('Segnala un problema', 'Report a problem'),
              sottotitolo: s.t('Hai visto qualcosa che non va? Bastano pochi secondi.', 'Spotted something wrong? It takes a few seconds.'),
              accento: Accento.arancio,
              piena: true,
              onTap: widget.onSegnalazioni,
            ),
          ),
          const SizedBox(height: 28),
          Appare(indice: 3, child: TitoloSezione(s.t('Scopri di più', 'Discover more'))),
          Appare(
            indice: 4,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _TesseraAzione(
                      icona: Icons.lightbulb_rounded,
                      titolo: s.t('Proponi un’idea', 'Share an idea'),
                      sottotitolo: s.t('Migliora il parco', 'Improve the park'),
                      accento: Accento.giallo,
                      verticale: true,
                      onTap: widget.onIdee,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TesseraAzione(
                      icona: Icons.notifications_rounded,
                      titolo: s.t('Avvisi del parco', 'Park notices'),
                      sottotitolo: s.t('Novità e lavori', 'News and works'),
                      accento: Accento.viola,
                      verticale: true,
                      onTap: widget.onAvvisi,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Riquadro toccabile della home: pieno (azione principale) o tenue.
class _TesseraAzione extends StatelessWidget {
  final IconData icona;
  final String titolo;
  final String sottotitolo;
  final Accento accento;
  final VoidCallback? onTap;
  final bool piena;
  final bool verticale;

  const _TesseraAzione({
    required this.icona,
    required this.titolo,
    required this.sottotitolo,
    required this.accento,
    required this.onTap,
    this.piena = false,
    this.verticale = false,
  });

  @override
  Widget build(BuildContext context) {
    final raggio = BorderRadius.circular(24);
    final coloreTitolo = piena ? Colors.white : testo;
    final coloreSotto = piena ? Colors.white.withValues(alpha: .88) : testoSecondario;

    final icon = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: piena ? Colors.white.withValues(alpha: .18) : superficie,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icona, color: piena ? Colors.white : accento.forte, size: 26),
    );
    final testi = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titolo, style: TextStyle(fontSize: piena ? 18 : 15.5, fontWeight: FontWeight.w800, color: coloreTitolo, height: 1.2)),
        const SizedBox(height: 3),
        Text(sottotitolo, style: TextStyle(fontSize: 13.5, height: 1.35, color: coloreSotto)),
      ],
    );

    return Semantics(
      button: true,
      label: titolo,
      hint: sottotitolo,
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: raggio,
          gradient: piena
              ? const LinearGradient(
                  colors: [Color(0xFFC0361B), Color(0xFFE8663D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: piena ? null : accento.tinta,
          border: piena ? null : Border.all(color: accento.base.withValues(alpha: .22)),
          boxShadow: piena
              ? const [BoxShadow(color: Color(0x40E4572E), blurRadius: 22, offset: Offset(0, 10))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: raggio,
            child: Padding(
              padding: EdgeInsets.all(verticale ? 16 : 18),
              child: verticale
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [icon, const SizedBox(height: 14), testi],
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: 14),
                        Expanded(child: testi),
                        Icon(Icons.arrow_forward_rounded, color: coloreTitolo),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
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
        _passaggio++;
      });
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
        _passaggio--;
      });
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
      setState(() => _passaggio = 1);
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
      final vediMappa = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const CircleAvatar(radius: 34, backgroundColor: menta, child: Icon(Icons.check_rounded, color: foresta, size: 40)),
          title: Text(s.t('Segnalazione inviata', 'Report submitted')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.t('Grazie! Il tuo aiuto rende il parco un posto migliore.', 'Thank you! Your help makes the park a better place.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: testoSecondario, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: sfondo, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text(
                      '${s.t('Numero segnalazione', 'Report number')}: ${result['code'] ?? result['id']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if ((result['status_label'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('${result['status_label']}', style: const TextStyle(color: testoSecondario)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (widget.onInviata != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.map_rounded),
                  label: Text(s.t('Vedi sulla mappa', 'See it on the map')),
                ),
              ),
              const SizedBox(height: 4),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s.t('Chiudi', 'Close'))),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _passaggio = 0; _categoria = null; _gravita = 'media';
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

    Widget linea(bool attiva) => AnimatedContainer(
          duration: durata(context, 300),
          height: 3,
          decoration: BoxDecoration(
            color: attiva ? foresta : bordo,
            borderRadius: BorderRadius.circular(3),
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
          boxShadow: corrente ? [const BoxShadow(color: Color(0x5517694A), blurRadius: 0, spreadRadius: 4)] : null,
        ),
        child: Center(
          child: completato
              ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: corrente ? Colors.white : testoSecondario,
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
          Text(titolo, style: const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.3)),
          const SizedBox(height: 6),
          Text(descrizione, style: const TextStyle(fontSize: 15, height: 1.45, color: testoSecondario)),
          const SizedBox(height: 18),
        ],
      );

  Widget _etichettaCampo(String testoCampo, [String? aiuto]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(testoCampo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: testo)),
            if (aiuto != null) ...[
              const SizedBox(height: 3),
              Text(aiuto, style: const TextStyle(fontSize: 13, height: 1.4, color: testoSecondario)),
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
      setState(() {
        _categoria = categoria.id;
        _errore = null;
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
        child: AnimatedContainer(
          duration: durata(context, 180),
          decoration: BoxDecoration(
            color: selezionata ? accento.tinta : superficie,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selezionata ? accento.base : bordo,
              width: selezionata ? 2 : 1,
            ),
            boxShadow: selezionata
                ? [BoxShadow(color: accento.base.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 6))]
                : const [BoxShadow(color: Color(0x0A12261B), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: selezionaCategoria,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                constraints: const BoxConstraints(minHeight: 112),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconaTonda(
                          categoria.icona,
                          colore: accento.forte,
                          sfondo: selezionata ? superficie : accento.tinta,
                          dimensione: 42,
                        ),
                        const Spacer(),
                        AnimatedScale(
                          scale: selezionata ? 1 : 0,
                          duration: durata(context, 200),
                          curve: Curves.easeOutBack,
                          child: Icon(Icons.check_circle_rounded, color: accento.forte, size: 24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      nome,
                      style: TextStyle(
                        color: testo,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: selezionata ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
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
            final larghezza = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categorie
                  .map((categoria) => SizedBox(width: larghezza, child: _schedaCategoria(categoria, s)))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        _etichettaCampo(
          s.t('Quanto è urgente?', 'How urgent is it?'),
          s.t('Se non sei sicuro, lascia «Media».', 'If unsure, leave “Medium”.'),
        ),
        _selettoreGravita(s),
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
          Expanded(child: Text(titolo, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: testo))),
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
          style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario),
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
          style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario),
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
            style: const TextStyle(fontSize: 12.5, color: testoSecondario),
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
          child: Text(titolo, style: const TextStyle(fontSize: 14, color: testoSecondario)),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Text(
            valore,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testo),
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
              Text(s.t('La tua segnalazione', 'Your report'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo)),
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
                Text(s.t('Descrizione', 'Description'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testoSecondario)),
                const SizedBox(height: 5),
                Text(_descrizione.text.trim(), style: const TextStyle(fontSize: 15, height: 1.45, color: testo)),
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
            duration: durata(context, 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: animazioni
                  ? SlideTransition(
                      position: Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero).animate(animation),
                      child: child,
                    )
                  : child,
            ),
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

class SchermataIdee extends StatefulWidget {
  final Copie s;
  const SchermataIdee({super.key, required this.s});
  @override
  State<SchermataIdee> createState() => _SchermataIdeeState();
}

class _SchermataIdeeState extends State<SchermataIdee> {
  static const Map<String, dynamic> _categoriaPredefinita = {'code': 'other', 'label': 'Altro'};

  bool _caricamento = true;
  String? _errore;
  List<_IdeaItem> _idee = [];
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

  Widget _schedaIdea(_IdeaItem idea, Copie s) {
    return Scheda(
      padding: const EdgeInsets.all(16),
      coloreBordo: idea.mine ? sole.withValues(alpha: .45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconaTonda(Icons.lightbulb_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(idea.title, style: const TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w800, color: testo)),
            if (idea.description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(idea.description, style: const TextStyle(fontSize: 14, height: 1.45, color: testoSecondario)),
            ],
          ])),
        ]),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.schedule_rounded, size: 15, color: testoTenue),
            const SizedBox(width: 5),
            Text([idea.dateLabel, if (idea.categoryLabel != null) idea.categoryLabel!].join(' · '), style: const TextStyle(fontSize: 13, color: testoSecondario)),
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
        icon: const IconaTonda(Icons.lightbulb_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 56),
        title: Text(s.t('Anteprima del suggerimento', 'Suggestion preview')),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: sfondo, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titolo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.3)),
              const SizedBox(height: 6),
              Text(dettagli, style: const TextStyle(color: testoSecondario, height: 1.4)),
              const SizedBox(height: 10),
              Etichetta('${s.t('Argomento', 'Topic')}: ${_nomeCategoria(_categoria)}', colore: soleScuro, sfondo: soleChiaro),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.public_rounded, size: 16, color: testoSecondario),
            const SizedBox(width: 6),
            Expanded(child: Text(s.t('Sarà visibile a tutti gli utenti dell’app.', 'It will be visible to all app users.'), style: const TextStyle(color: testoSecondario, fontSize: 13))),
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
              const IconaTonda(Icons.edit_note_rounded, colore: soleScuro, sfondo: soleChiaro, dimensione: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('La tua idea', 'Your idea'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: testo)),
                const SizedBox(height: 3),
                Text(s.t('Raccontaci cosa migliorerebbe il parco.', 'Tell us what could make the park better.'), style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario)),
              ])),
            ]),
            const SizedBox(height: 18),
            TextField(controller: widget.titolo, autofocus: true, textCapitalization: TextCapitalization.sentences, maxLength: 120, decoration: InputDecoration(labelText: s.t('Titolo', 'Title'), hintText: s.t('Es. Più ombra vicino all’area giochi', 'E.g. More shade near the playground'))),
            const SizedBox(height: 10),
            TextField(controller: widget.dettagli, minLines: 3, maxLines: 4, maxLength: 870, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: s.t('Descrizione', 'Description'), hintText: s.t('Descrivi la tua idea in poche parole…', 'Describe your idea in a few words…'), helperText: s.t('Non inserire dati personali.', 'Do not include personal information.'), alignLabelWithHint: true)),
            const SizedBox(height: 14),
            Text(s.t('Argomento', 'Topic'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: testo)),
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
  final String categoria;
  final String? statoManutenzione;
  final IconData icona;
  final Color colore;
  final String titoloIt;
  final String titoloEn;
  final String descrizioneIt;
  final String descrizioneEn;
  final String data;

  const Avviso({
    required this.categoria,
    this.statoManutenzione,
    required this.icona,
    required this.colore,
    required this.titoloIt,
    required this.titoloEn,
    required this.descrizioneIt,
    required this.descrizioneEn,
    required this.data,
  });
}

class SchermataAvvisi extends StatefulWidget {
  final Copie s;
  /// Cambia ogni volta che l'utente apre la scheda: gli avvisi si ricaricano.
  final int aperture;
  const SchermataAvvisi({super.key, required this.s, this.aperture = 0});

  @override
  State<SchermataAvvisi> createState() => _SchermataAvvisiState();
}

class _SchermataAvvisiState extends State<SchermataAvvisi> {
  String _filtro = 'tutti';
  List<Avviso> _avvisi = [];
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
          categoria: category,
          icona: level == 'alert' ? Icons.priority_high_rounded : level == 'warning' ? Icons.handyman_rounded : Icons.new_releases_rounded,
          colore: level == 'alert' ? coralloScuro : level == 'warning' ? soleScuro : cieloScuro,
          titoloIt: item['title'] as String? ?? '',
          titoloEn: item['title'] as String? ?? '',
          descrizioneIt: item['body'] as String? ?? '',
          descrizioneEn: item['body'] as String? ?? '',
          data: formattaData(item['starts_at']),
        );
      }).toList();
      if (mounted) setState(() { _avvisi = parsed; _caricamento = false; _errore = null; });
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
    return Scheda(
      padding: const EdgeInsets.all(16),
      colore: importante ? const Color(0xFFFFF7F5) : superficie,
      coloreBordo: importante ? corallo.withValues(alpha: .40) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconaTonda(avviso.icona, colore: avviso.colore, dimensione: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _etichettaCategoria(s, avviso.categoria, avviso.statoManutenzione),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: avviso.colore),
                    ),
                    if (avviso.data.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(avviso.data, style: const TextStyle(fontSize: 12.5, color: testoSecondario)),
                    ],
                  ],
                ),
              ),
              if (importante) Etichetta(s.t('DA LEGGERE', 'PLEASE READ'), colore: coralloScuro, sfondo: coralloChiaro),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.t(avviso.titoloIt, avviso.titoloEn),
            style: const TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w800, color: testo),
          ),
          if (s.t(avviso.descrizioneIt, avviso.descrizioneEn).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.t(avviso.descrizioneIt, avviso.descrizioneEn),
              style: const TextStyle(fontSize: 14.5, height: 1.5, color: testoSecondario),
            ),
          ],
        ],
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filtroAvvisi('tutti', s.t('Tutti', 'All'), Icons.apps_rounded, Accento.viola),
                _filtroAvvisi('importante', s.t('Importanti', 'Important'), Icons.priority_high_rounded, Accento.arancio),
                _filtroAvvisi('manutenzione', s.t('Manutenzione', 'Maintenance'), Icons.handyman_rounded, Accento.giallo),
                _filtroAvvisi('novita', s.t('Novità', 'News'), Icons.new_releases_rounded, Accento.blu),
              ],
            ),
            const SizedBox(height: 22),
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
