import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'citizen_api.dart';
import 'mappa_parco.dart';
import 'ui.dart';

/// Mappa delle segnalazioni del parco.
///
/// La mappa occupa tutta la pagina; sopra ci sono i filtri, sotto un pannello
/// che si trascina verso l'alto con l'elenco e il dettaglio della segnalazione
/// scelta. Così si scorre l'elenco senza mai trascinare la mappa per sbaglio.
/// Si aggiorna in tempo reale dal WebSocket /citizen/ws.
class SchermataSegnalazioni extends StatefulWidget {
  final Copie s;
  /// Segnalazione da aprire appena l'elenco è caricato (es. dalle fonti dell'assistente).
  final int? apri;
  /// Parte dal filtro «solo le mie».
  final bool soloMie;
  const SchermataSegnalazioni({super.key, required this.s, this.apri, this.soloMie = false});

  @override
  State<SchermataSegnalazioni> createState() => _SchermataSegnalazioniState();
}

/// Stati di una segnalazione, nell'ordine in cui avanzano.
const List<(String, String, String)> _stati = [
  ('received', 'Ricevute', 'Received'),
  ('in_progress', 'In corso', 'In progress'),
  ('resolved', 'Risolte', 'Resolved'),
  ('closed', 'Chiuse', 'Closed'),
];

String _statoDi(Map<String, dynamic> r) {
  final st = r['status'];
  return st == 'in_progress' || st == 'resolved' || st == 'closed' ? st as String : 'received';
}

class _SchermataSegnalazioniState extends State<SchermataSegnalazioni> with TickerProviderStateMixin {
  late bool _soloMie = widget.soloMie;
  /// Stato scelto nei filtri; nullo = tutti.
  String? _filtroStato;
  /// Segnalazione scelta (per id).
  Object? _selezionata;

  bool _caricamento = true;
  String? _errore;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription<Map<String, dynamic>>? _live;
  Timer? _debounce;

  final MapController _mappa = MapController();
  late final AnimatoreMappa _volo = AnimatoreMappa(_mappa, this);
  final DraggableScrollableController _foglio = DraggableScrollableController();
  ScrollController? _scrollFoglio;
  double _altezza = 600;

  /// Spazio occupato in alto dalla barra dei filtri.
  static const double _altezzaFiltri = 58;
  /// Altezza del pannello chiuso: maniglia e intestazione.
  static const double _foglioMinimoPx = 96;
  static const double _foglioIniziale = .40;

  @override
  void initState() {
    super.initState();
    unawaited(_carica().then((_) => _apriRichiesta()));
    CitizenApi.instance.connectLive();
    _live = CitizenApi.instance.events.listen((e) {
      final type = e['type'];
      if (type == 'report_updated' || type == 'report_created' || type == 'report_status_changed') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () => _carica(silenzioso: true));
      }
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    _volo.dispose();
    _foglio.dispose();
    _mappa.dispose();
    super.dispose();
  }

  Future<void> _carica({bool silenzioso = false}) async {
    if (!silenzioso && mounted) {
      setState(() {
        _caricamento = true;
        _errore = null;
      });
    }
    try {
      final data = _soloMie
          ? await CitizenApi.instance.getMyReports(limit: 50)
          // Le idee (suggestion) hanno la loro schermata: qui solo i problemi
          : await CitizenApi.instance.getFeed(kind: 'problem', limit: 50);
      var rows = (data['items'] as List).cast<Map<String, dynamic>>();
      if (_soloMie) rows = await _conPosizione(rows);
      if (mounted) {
        setState(() {
          _items = rows;
          _caricamento = false;
          _errore = null;
          if (!rows.any((r) => r['id'] == _selezionata)) _selezionata = null;
        });
      }
    } catch (e) {
      final notFound = e is ApiException && e.statusCode == 404;
      if (mounted) {
        setState(() {
          _caricamento = false;
          _errore = notFound
              ? widget.s.t('Elenco non ancora disponibile sul server.', 'List not available on the server yet.')
              : e.toString();
        });
      }
    }
  }

  /// Apre la segnalazione indicata in [SchermataSegnalazioni.apri], anche se non è in elenco.
  Future<void> _apriRichiesta() async {
    final id = widget.apri;
    if (id == null || !mounted) return;
    if (_items.any((r) => r['id'] == id)) _seleziona(id, avvicina: true);
    await _dettaglio(_items.where((r) => r['id'] == id).firstOrNull ?? {'id': id});
  }

  /// Il server reale mette la posizione solo nel dettaglio della segnalazione:
  /// per le proprie la si recupera da lì, così compaiono sulla mappa.
  /// (Quella delle segnalazioni altrui non viene mai inviata, per privacy.)
  Future<List<Map<String, dynamic>>> _conPosizione(List<Map<String, dynamic>> rows) {
    return Future.wait(rows.map((r) async {
      if (MappaParco.puntoDi(r) != null || r['id'] is! int) return r;
      try {
        final d = await CitizenApi.instance.getReport(r['id'] as int);
        return {...r, ...d};
      } catch (_) {
        return r;
      }
    }));
  }

  List<Map<String, dynamic>> get _visibili =>
      _filtroStato == null ? _items : _items.where((r) => _statoDi(r) == _filtroStato).toList();

  // ── Movimenti di mappa e pannello ─────────────────────────────────────────

  bool get _animazioni => !MediaQuery.of(context).disableAnimations;

  /// Altezza in pixel che il pannello avrà dopo una selezione.
  double get _foglioPx {
    final attuale = _foglio.isAttached ? _foglio.pixels : 0.0;
    return math.max(attuale, _foglioIniziale * _altezza);
  }

  /// Porta [p] nella parte di mappa visibile tra filtri e pannello.
  /// Senza [zoom] la mappa si muove solo se il punto è coperto.
  void _mostraSullaMappa(LatLng p, {double? zoom}) {
    final MapCamera cam;
    try {
      cam = _mappa.camera;
    } catch (_) {
      return; // mappa non ancora pronta
    }
    final foglio = _foglioPx;
    final schermo = cam.latLngToScreenOffset(p);
    final coperto = schermo.dy < _altezzaFiltri + 30 ||
        schermo.dy > _altezza - foglio - 30 ||
        schermo.dx < 24 ||
        schermo.dx > cam.nonRotatedSize.width - 24;
    if (zoom == null && !coperto) return;
    final z = zoom ?? cam.zoom;
    final centro = cam.unprojectAtZoom(cam.projectAtZoom(p, z) + Offset(0, (foglio - _altezzaFiltri) / 2), z);
    _volo.vola(centro, z, animato: _animazioni);
  }

  void _seleziona(Object? id, {bool avvicina = false}) {
    setState(() => _selezionata = id);
    if (id == null) return;
    final d = durata(context, 320);
    if (_foglio.isAttached && _foglio.size < _foglioIniziale - .01) {
      _foglio.animateTo(_foglioIniziale, duration: d == Duration.zero ? const Duration(milliseconds: 1) : d, curve: Curves.easeOutCubic);
    }
    final scroll = _scrollFoglio;
    if (scroll != null && scroll.hasClients && scroll.offset > 0) {
      if (_animazioni) {
        scroll.animateTo(0, duration: d, curve: Curves.easeOutCubic);
      } else {
        scroll.jumpTo(0);
      }
    }
    final r = _items.where((e) => e['id'] == id).firstOrNull;
    final p = r == null ? null : MappaParco.puntoDi(r);
    if (p != null) {
      double? zoom;
      if (avvicina) {
        try {
          zoom = math.max(_mappa.camera.zoom, 17.5);
        } catch (_) {}
      }
      _mostraSullaMappa(p, zoom: zoom);
    }
  }

  /// Tocco su un gruppo: si avvicina finché i segnaposto si separano; se sono
  /// nello stesso punto anche allo zoom massimo, si sceglie da un elenco.
  void _apriGruppo(List<(Map<String, dynamic>, LatLng)> gruppo) {
    final cam = _mappa.camera;
    final inseparabili = LivelloGruppi.raggruppa(cam, gruppo, MappaParco.zoomMassimo).length == 1;
    if (inseparabili || cam.zoom >= MappaParco.zoomMassimo - .05) {
      unawaited(_scegliDalGruppo(gruppo));
      return;
    }
    final adatta = CameraFit.coordinates(
      coordinates: [for (final e in gruppo) e.$2],
      padding: EdgeInsets.fromLTRB(56, _altezzaFiltri + 40, 56, _foglioPx + 40),
      maxZoom: MappaParco.zoomMassimo,
    ).fit(cam);
    final zoom = math.max(adatta.zoom, cam.zoom + 1).clamp(13, MappaParco.zoomMassimo).toDouble();
    _volo.vola(adatta.center, zoom, animato: _animazioni);
  }

  Future<void> _scegliDalGruppo(List<(Map<String, dynamic>, LatLng)> gruppo) async {
    final s = widget.s;
    final scelta = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  s.t('${gruppo.length} segnalazioni in questo punto', '${gruppo.length} reports at this spot'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              for (final (r, _) in gruppo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _riga(r, onTap: () => Navigator.of(ctx).pop(r['id'])),
                ),
            ],
          ),
        ),
      ),
    );
    if (scelta != null && mounted) _seleziona(scelta);
  }

  // ── Schede ────────────────────────────────────────────────────────────────

  /// Scheda completa della segnalazione scelta.
  Widget _scheda(Map<String, dynamic> r) {
    final s = widget.s;
    final testoDescr = (r['description'] ?? r['summary'] ?? '').toString();
    final foto = CitizenApi.instance.absoluteUrl(r['photo_url'] as String?);
    final mia = r['is_mine'] == true || _soloMie;
    final categoria = (r['category_label'] ?? r['category'] ?? '').toString();
    final codice = (r['code'] ?? '').toString();
    final rating = r['rating'];
    final statoLabel = r['status_label']?.toString() ?? '';
    final coloreStato = coloreStatoSegnalazione(r['status'] as String?);

    return Scheda(
      padding: EdgeInsets.zero,
      coloreBordo: coloreStato.withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (foto != null) FotoApribile(url: foto, etichetta: s.t('Foto, tocca per ingrandire', 'Photo, tap to enlarge')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoria.isNotEmpty ? categoria : codice,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo, height: 1.25),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (statoLabel.isNotEmpty) Etichetta(statoLabel, colore: coloreStato, puntino: true),
                              if (r['is_mine'] == true && !_soloMie)
                                Etichetta(s.t('Tua', 'Yours'), icona: Icons.person_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('Chiudi', 'Close'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _selezionata = null),
                      icon: Icon(Icons.close_rounded, color: testoSecondario),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (testoDescr.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(testoDescr, style: TextStyle(fontSize: 14.5, color: testo, height: 1.45)),
                      ],
                      if (rating is int && rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(children: List.generate(rating, (_) => const Icon(Icons.star_rounded, size: 18, color: sole))),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 15, color: testoTenue),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              [formattaData(r['created_at'], ora: true), if (codice.isNotEmpty && categoria.isNotEmpty) codice]
                                  .join('  ·  '),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: testoSecondario),
                            ),
                          ),
                        ],
                      ),
                      if (mia && r['id'] is int) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => _dettaglio(r),
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: Text(s.t('Vedi lo storico', 'See history')),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Riga compatta dell'elenco: miniatura, categoria, descrizione e stato.
  Widget _riga(Map<String, dynamic> r, {VoidCallback? onTap}) {
    final s = widget.s;
    final foto = immagineDa(CitizenApi.instance.absoluteUrl(r['photo_url'] as String?));
    final categoria = (r['category_label'] ?? r['category'] ?? r['code'] ?? '').toString();
    final descr = (r['description'] ?? r['summary'] ?? '').toString();
    final coloreStato = coloreStatoSegnalazione(r['status'] as String?);
    final senzaPosizione = MappaParco.puntoDi(r) == null;

    return Scheda(
      padding: const EdgeInsets.all(10),
      onTap: onTap ?? () => _seleziona(r['id'], avvicina: true),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 58,
              height: 58,
              child: foto != null
                  ? Image(
                      image: foto,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _iconaRiga(r, coloreStato),
                    )
                  : _iconaRiga(r, coloreStato),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        categoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: testo),
                      ),
                    ),
                    if (r['is_mine'] == true && !_soloMie) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.person_rounded, size: 15, color: foresta, semanticLabel: s.t('Tua', 'Yours')),
                    ],
                  ],
                ),
                if (descr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    descr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: testoSecondario),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Etichetta(r['status_label']?.toString() ?? '', colore: coloreStato, puntino: true),
                    ),
                    const SizedBox(width: 8),
                    Text(formattaData(r['created_at']), style: TextStyle(fontSize: 12, color: testoTenue)),
                    if (senzaPosizione) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.location_off_rounded, size: 14, color: testoTenue,
                          semanticLabel: s.t('senza posizione', 'no location')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconaRiga(Map<String, dynamic> r, Color colore) => ColoredBox(
        color: colore.withValues(alpha: .12),
        child: Icon(iconaCategoria(r['category'] as String?), color: colore, size: 26),
      );

  Future<void> _dettaglio(Map<String, dynamic> r) async {
    final s = widget.s;
    Map<String, dynamic> d = r;
    try {
      d = await CitizenApi.instance.getReport(r['id'] as int);
    } catch (_) {}
    if (!mounted) return;
    final storico = (d['history'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconaTonda(Icons.receipt_long_rounded, colore: cieloScuro, sfondo: cieloChiaro, dimensione: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['code']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Etichetta('${d['status_label']}', colore: coloreStatoSegnalazione(d['status'] as String?), puntino: true),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(s.t('Storico', 'History'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              for (final (i, h) in storico.indexed)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Column(
                          children: [
                            const SizedBox(height: 3),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == storico.length - 1 ? foresta : superficie,
                                border: Border.all(color: foresta, width: 2),
                              ),
                            ),
                            if (i < storico.length - 1) Expanded(child: Container(width: 2, color: bordo)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${h['status']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text(formattaData(h['at'], ora: true), style: TextStyle(fontSize: 12.5, color: testoSecondario)),
                              if (h['note'] != null) ...[
                                const SizedBox(height: 4),
                                Text('${h['note']}', style: const TextStyle(fontSize: 14, height: 1.4)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filtri ────────────────────────────────────────────────────────────────

  static const List<BoxShadow> _ombraFlottante = [
    BoxShadow(color: Color(0x2612261B), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// «Tutte / Mie»: un unico interruttore a due posizioni.
  Widget _interruttoreChi(Copie s) {
    Widget voce(bool mie, IconData icona, String testoVoce) {
      final attiva = _soloMie == mie;
      return Semantics(
        button: true,
        selected: attiva,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: attiva
              ? null
              : () {
                  setState(() {
                    _soloMie = mie;
                    _selezionata = null;
                  });
                  unawaited(_carica());
                },
          child: AnimatedContainer(
            duration: durata(context, 180),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: attiva ? foresta : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icona, size: 17, color: attiva ? Colors.white : testoSecondario),
                const SizedBox(width: 5),
                Text(
                  testoVoce,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: attiva ? Colors.white : testoSecondario,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: superficie,
        borderRadius: BorderRadius.circular(21),
        boxShadow: _ombraFlottante,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            voce(false, Icons.groups_rounded, s.t('Tutte', 'All')),
            voce(true, Icons.person_rounded, s.t('Mie', 'Mine')),
          ],
        ),
      ),
    );
  }

  /// Filtro per stato: il puntino colorato è anche la legenda dei segnaposto.
  Widget _chipStato(String stato, String etichetta, int quanti) {
    final attivo = _filtroStato == stato;
    final colore = coloreStatoSegnalazione(stato);
    return Semantics(
      button: true,
      selected: attivo,
      label: '$etichetta, $quanti',
      excludeSemantics: true,
      child: Material(
        color: attivo ? colore : superficie,
        shape: const StadiumBorder(),
        shadowColor: const Color(0x4012261B),
        elevation: 3,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() {
            _filtroStato = attivo ? null : stato;
            if (_selezionata != null && !_visibili.any((r) => r['id'] == _selezionata)) _selezionata = null;
          }),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: attivo ? Colors.white : colore,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  etichetta,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: attivo ? Colors.white : testo),
                ),
                const SizedBox(width: 6),
                Text(
                  '$quanti',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: attivo ? Colors.white.withValues(alpha: .85) : testoTenue,
                  ),
                ),
                if (attivo) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.close_rounded, size: 15, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barraFiltri(Copie s) {
    final conteggi = <String, int>{};
    for (final r in _items) {
      conteggi.update(_statoDi(r), (n) => n + 1, ifAbsent: () => 1);
    }
    return SizedBox(
      height: _altezzaFiltri,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        clipBehavior: Clip.none,
        children: [
          Center(child: _interruttoreChi(s)),
          const SizedBox(width: 8),
          for (final (stato, it, en) in _stati) ...[
            Center(child: _chipStato(stato, s.t(it, en), conteggi[stato] ?? 0)),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  // ── Pannello ──────────────────────────────────────────────────────────────

  List<Widget> _contenutoFoglio(Copie s) {
    if (_caricamento) {
      return [CaricamentoScheletro(numero: 2, etichetta: s.t('Caricamento delle segnalazioni', 'Loading reports'))];
    }
    if (_errore != null) {
      return [
        StatoVuoto(
          icona: Icons.cloud_off_rounded,
          messaggio: _errore!,
          accento: Accento.arancio,
          onAzione: _carica,
          etichettaAzione: s.t('Riprova', 'Retry'),
        ),
      ];
    }
    final visibili = _visibili;
    if (visibili.isEmpty) {
      return [
        StatoVuoto(
          icona: Icons.inbox_outlined,
          accento: Accento.blu,
          messaggio: _filtroStato != null
              ? s.t('Nessuna segnalazione con questo stato.', 'No reports with this status.')
              : _soloMie
                  ? s.t('Non hai ancora inviato segnalazioni.', 'You have not sent any reports yet.')
                  : s.t('Nessuna segnalazione.', 'No reports.'),
        ),
      ];
    }
    final scelta = visibili.where((r) => r['id'] == _selezionata).firstOrNull;
    final altre = [for (final r in visibili) if (r['id'] != _selezionata) r];
    return [
      if (scelta != null) ...[
        KeyedSubtree(key: ValueKey('scelta-${scelta['id']}'), child: Appare(child: _scheda(scelta))),
        if (altre.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
            child: Text(
              s.t('Altre segnalazioni', 'Other reports'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: testoSecondario),
            ),
          ),
      ],
      for (final r in altre)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: KeyedSubtree(key: ValueKey('riga-${r['id']}'), child: _riga(r)),
        ),
    ];
  }

  /// Nota breve sotto l'intestazione del pannello, solo se serve.
  String? _nota(Copie s, int conPosizione) {
    if (_caricamento || _errore != null || _items.isEmpty) return null;
    final senza = _visibili.length - conPosizione;
    if (conPosizione == 0 && !_soloMie) {
      return s.t('Le posizioni degli altri non sono pubbliche: scegli «Mie» per vedere le tue.',
          'Other people’s locations are private: choose “Mine” to see yours.');
    }
    if (senza > 0) return s.t('$senza senza posizione, solo in elenco.', '$senza without location, list only.');
    return null;
  }

  Widget _foglioScorrevole(Copie s, ScrollController scroll, int conPosizione) {
    _scrollFoglio = scroll;
    final nota = _nota(s, conPosizione);
    final totale = _visibili.length;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [BoxShadow(color: Color(0x2E12261B), blurRadius: 24, offset: Offset(0, -4))],
          ),
          child: Material(
            color: sfondo,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(color: bordoForte, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            _soloMie ? s.t('Le mie segnalazioni', 'My reports') : s.t('Segnalazioni', 'Reports'),
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.2),
                          ),
                        ),
                      ),
                      if (!_caricamento && _errore == null)
                        Etichetta('$totale', colore: cieloScuro, sfondo: cieloChiaro),
                      IconButton(
                        tooltip: s.t('Aggiorna', 'Refresh'),
                        onPressed: _caricamento ? null : () => _carica(),
                        icon: Icon(Icons.refresh_rounded, color: testoSecondario),
                      ),
                    ],
                  ),
                ),
                if (nota != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 15, color: testoTenue),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(nota, style: TextStyle(fontSize: 12.5, color: testoSecondario, height: 1.35))),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                ..._contenutoFoglio(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final conPosizione = [
      for (final r in _visibili)
        if (MappaParco.puntoDi(r) case final punto?) (r, punto),
    ];

    return LayoutBuilder(
      builder: (context, vincoli) {
        _altezza = vincoli.maxHeight;
        final minimo = (_foglioMinimoPx / _altezza).clamp(.08, .3);
        final massimo = ((_altezza - _altezzaFiltri) / _altezza).clamp(.5, 1.0);
        final iniziale = _foglioIniziale.clamp(minimo, massimo);
        final aggancio = minimo < iniziale && iniziale < massimo;

        return Stack(
          fit: StackFit.expand,
          children: [
            MappaParco(
              altezza: null,
              controller: _mappa,
              centro: MappaParco.centroParco(conPosizione.map((e) => e.$2)),
              margineAttribuzione: const EdgeInsets.only(top: _altezzaFiltri - 4),
              allineamentoAttribuzione: Alignment.topRight,
              onTocco: (_) {
                if (_selezionata != null) setState(() => _selezionata = null);
              },
              livelli: [
                LivelloGruppi<Map<String, dynamic>>(
                  punti: conPosizione,
                  scelto: (r) => r['id'] == _selezionata,
                  etichettaGruppo: (n) => s.t('$n segnalazioni vicine, tocca per vederle', '$n nearby reports, tap to see them'),
                  onGruppo: _apriGruppo,
                  segnaposto: (r) => Semantics(
                    button: true,
                    label: '${r['category_label'] ?? r['code']}, ${r['status_label'] ?? ''}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _seleziona(r['id']),
                      child: Segnaposto(
                        icona: iconaCategoria(r['category'] as String?),
                        colore: coloreStatoSegnalazione(r['status'] as String?),
                        selezionato: r['id'] == _selezionata,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(top: 0, left: 0, right: 0, child: _barraFiltri(s)),
            DraggableScrollableSheet(
              controller: _foglio,
              minChildSize: minimo,
              initialChildSize: iniziale,
              maxChildSize: massimo,
              snap: true,
              snapSizes: aggancio ? [iniziale] : null,
              builder: (context, scroll) => _foglioScorrevole(s, scroll, conPosizione.length),
            ),
          ],
        );
      },
    );
  }
}
