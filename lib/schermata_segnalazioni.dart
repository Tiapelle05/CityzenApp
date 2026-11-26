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
  /// Carosello delle segnalazioni in basso: scorrendo le schede la mappa segue.
  final PageController _carosello = PageController(viewportFraction: .9);

  /// Spazio occupato in alto dalla barra dei filtri.
  static const double _altezzaFiltri = 58;
  /// Spazio occupato in basso da carosello e pulsante dell'elenco.
  static const double _ingombroBasso = 170;

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
    _carosello.dispose();
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

  // ── Movimenti di mappa e carosello ────────────────────────────────────────

  bool get _animazioni => !MediaQuery.of(context).disableAnimations;

  /// Porta [p] nella parte di mappa visibile tra filtri e carosello.
  /// Senza [zoom] la mappa si muove solo se il punto è coperto.
  void _mostraSullaMappa(LatLng p, {double? zoom}) {
    final MapCamera cam;
    try {
      cam = _mappa.camera;
    } catch (_) {
      return; // mappa non ancora pronta
    }
    const foglio = _ingombroBasso;
    final altezza = cam.nonRotatedSize.height;
    final schermo = cam.latLngToScreenOffset(p);
    final coperto = schermo.dy < _altezzaFiltri + 30 ||
        schermo.dy > altezza - foglio - 30 ||
        schermo.dx < 24 ||
        schermo.dx > cam.nonRotatedSize.width - 24;
    if (zoom == null && !coperto) return;
    final z = zoom ?? cam.zoom;
    final centro = cam.unprojectAtZoom(cam.projectAtZoom(p, z) + Offset(0, (foglio - _altezzaFiltri) / 2), z);
    _volo.vola(centro, z, animato: _animazioni);
  }

  /// Sceglie una segnalazione: il carosello va alla sua scheda (se la scelta
  /// non arriva proprio dal carosello) e la mappa mostra il suo segnaposto.
  void _seleziona(Object? id, {bool avvicina = false, bool muoviCarosello = true}) {
    setState(() => _selezionata = id);
    if (id == null) return;
    final indice = _visibili.indexWhere((r) => r['id'] == id);
    if (muoviCarosello && indice >= 0 && _carosello.hasClients && _carosello.page?.round() != indice) {
      final d = durata(context, 320);
      if (d == Duration.zero) {
        _carosello.jumpToPage(indice);
      } else {
        _carosello.animateToPage(indice, duration: d, curve: Curves.easeOutCubic);
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
      padding: const EdgeInsets.fromLTRB(56, _altezzaFiltri + 40, 56, _ingombroBasso + 40),
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

  /// Scheda completa della segnalazione, aperta toccando una scheda del carosello.
  Widget _scheda(Map<String, dynamic> r, {required VoidCallback onChiudi}) {
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
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo, height: 1.25),
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
                      onPressed: onChiudi,
                      icon: const Icon(Icons.close_rounded, color: testoSecondario),
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
                        Text(testoDescr, style: const TextStyle(fontSize: 14.5, color: testo, height: 1.45)),
                      ],
                      if (rating is int && rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(children: List.generate(rating, (_) => const Icon(Icons.star_rounded, size: 18, color: sole))),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 15, color: testoTenue),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              [formattaData(r['created_at'], ora: true), if (codice.isNotEmpty && categoria.isNotEmpty) codice]
                                  .join('  ·  '),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: testoSecondario),
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

  /// Riga compatta: miniatura, categoria, descrizione e stato. È la scheda del
  /// carosello e la riga dell'elenco completo; [scelta] la evidenzia.
  Widget _riga(Map<String, dynamic> r, {VoidCallback? onTap, bool scelta = false}) {
    final s = widget.s;
    final foto = immagineDa(CitizenApi.instance.absoluteUrl(r['photo_url'] as String?));
    final categoria = (r['category_label'] ?? r['category'] ?? r['code'] ?? '').toString();
    final descr = (r['description'] ?? r['summary'] ?? '').toString();
    final coloreStato = coloreStatoSegnalazione(r['status'] as String?);
    final senzaPosizione = MappaParco.puntoDi(r) == null;

    return Scheda(
      padding: const EdgeInsets.all(10),
      coloreBordo: scelta ? Accento.blu.base : null,
      onTap: onTap ?? () => _apriScheda(r),
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: testo),
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
                    style: const TextStyle(fontSize: 13, color: testoSecondario),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Etichetta(r['status_label']?.toString() ?? '', colore: coloreStato, puntino: true),
                    ),
                    const SizedBox(width: 8),
                    Text(formattaData(r['created_at']), style: const TextStyle(fontSize: 12, color: testoTenue)),
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
                  const IconaTonda(Icons.receipt_long_rounded, colore: cieloScuro, sfondo: cieloChiaro, dimensione: 48),
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
                              Text(formattaData(h['at'], ora: true), style: const TextStyle(fontSize: 12.5, color: testoSecondario)),
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

  /// Filtro per stato in un solo menu: le voci hanno il puntino colorato
  /// (la legenda dei segnaposto) e quante segnalazioni ci sono.
  Widget _menuStato(Copie s, Map<String, int> conteggi) {
    final scelto = _filtroStato;
    final etichetta = scelto == null
        ? s.t('Tutti gli stati', 'All statuses')
        : _stati.where((x) => x.$1 == scelto).map((x) => s.t(x.$2, x.$3)).first;
    Widget puntino(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return PopupMenuButton<String>(
      tooltip: s.t('Filtra per stato', 'Filter by status'),
      onSelected: (v) => setState(() {
        _filtroStato = v.isEmpty ? null : v;
        if (_selezionata != null && !_visibili.any((r) => r['id'] == _selezionata)) _selezionata = null;
      }),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: '',
          checked: scelto == null,
          child: Text('${s.t('Tutti gli stati', 'All statuses')} (${_items.length})'),
        ),
        for (final (stato, it, en) in _stati)
          CheckedPopupMenuItem(
            value: stato,
            checked: scelto == stato,
            child: Row(
              children: [
                puntino(coloreStatoSegnalazione(stato)),
                const SizedBox(width: 8),
                Text('${s.t(it, en)} (${conteggi[stato] ?? 0})'),
              ],
            ),
          ),
      ],
      child: Material(
        color: scelto == null ? superficie : coloreStatoSegnalazione(scelto),
        shape: const StadiumBorder(),
        shadowColor: const Color(0x4012261B),
        elevation: 3,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (scelto != null) ...[puntino(Colors.white), const SizedBox(width: 6)],
              Text(
                etichetta,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: scelto == null ? testo : Colors.white),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: scelto == null ? testoSecondario : Colors.white),
            ],
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
        padding: const EdgeInsets.fromLTRB(margineLaterale, 8, margineLaterale, 4),
        clipBehavior: Clip.none,
        children: [
          Center(child: _interruttoreChi(s)),
          const SizedBox(width: 8),
          Center(child: _menuStato(s, conteggi)),
        ],
      ),
    );
  }

  // ── Carosello ─────────────────────────────────────────────────────────────

  /// Dettaglio completo di una segnalazione in un foglio che si chiude con un
  /// gesto: la mappa resta libera finché non serve.
  Future<void> _apriScheda(Map<String, dynamic> r) async {
    _seleziona(r['id']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sfondo,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(margineLaterale, 0, margineLaterale, 20),
            child: _scheda(r, onChiudi: () => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    );
  }

  /// Elenco completo, aperto dal pulsante sopra il carosello.
  Future<void> _apriElenco(Copie s) async {
    final scelta = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sfondo,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (ctx, scroll) {
          final visibili = _visibili;
          return ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(margineLaterale, 0, margineLaterale, 24),
            itemCount: visibili.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            _soloMie ? s.t('Le mie segnalazioni', 'My reports') : s.t('Segnalazioni', 'Reports'),
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.2),
                          ),
                        ),
                      ),
                      Etichetta('${visibili.length}', colore: cieloScuro, sfondo: cieloChiaro),
                    ],
                  ),
                );
              }
              final r = visibili[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _riga(r, scelta: r['id'] == _selezionata, onTap: () => Navigator.of(ctx).pop(r['id'])),
              );
            },
          );
        },
      ),
    );
    if (scelta != null && mounted) _seleziona(scelta, avvicina: true);
  }

  /// Pulsante a pillola sopra il carosello: quante sono e apre l'elenco completo.
  Widget _pulsanteElenco(Copie s, int totale) => Material(
        color: superficie,
        shape: const StadiumBorder(),
        shadowColor: const Color(0x4012261B),
        elevation: 3,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _apriElenco(s),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.view_list_rounded, size: 18, color: cieloScuro),
                const SizedBox(width: 6),
                Text(
                  totale == 1 ? s.t('1 segnalazione', '1 report') : s.t('$totale segnalazioni', '$totale reports'),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: testo),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_less_rounded, size: 18, color: testoSecondario),
              ],
            ),
          ),
        ),
      );

  /// Avviso a pillola sotto i filtri quando la mappa è vuota per privacy.
  Widget _notaPrivacy(Copie s) => Material(
        color: superficie,
        shape: const StadiumBorder(),
        shadowColor: const Color(0x4012261B),
        elevation: 3,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            setState(() {
              _soloMie = true;
              _selezionata = null;
            });
            unawaited(_carica());
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16, color: testoSecondario),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: s.t('Le posizioni degli altri sono private · ', 'Others’ locations are private · ')),
                      TextSpan(
                        text: s.t('Vedi le mie', 'See mine'),
                        style: const TextStyle(color: foresta, fontWeight: FontWeight.w800),
                      ),
                    ]),
                    style: const TextStyle(fontSize: 12.5, color: testoSecondario, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// Contenuto del carosello: le schede, oppure caricamento, errore o vuoto.
  Widget _caroselloSchede(Copie s) {
    Widget unica(Widget figlio) => Padding(padding: const EdgeInsets.symmetric(horizontal: margineLaterale), child: figlio);
    if (_caricamento) {
      return unica(Scheda(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 12),
          Text(s.t('Caricamento delle segnalazioni…', 'Loading reports…'), style: const TextStyle(color: testoSecondario)),
        ]),
      ));
    }
    if (_errore != null) {
      return unica(Scheda(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: coralloScuro),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_errore!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: testo)),
          ),
          TextButton(onPressed: _carica, child: Text(s.t('Riprova', 'Retry'))),
        ]),
      ));
    }
    final visibili = _visibili;
    if (visibili.isEmpty) {
      return unica(Scheda(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          const Icon(Icons.inbox_outlined, color: testoSecondario),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _filtroStato != null
                  ? s.t('Nessuna segnalazione con questo stato.', 'No reports with this status.')
                  : _soloMie
                      ? s.t('Non hai ancora inviato segnalazioni.', 'You have not sent any reports yet.')
                      : s.t('Nessuna segnalazione.', 'No reports.'),
              style: const TextStyle(fontSize: 14, color: testoSecondario),
            ),
          ),
        ]),
      ));
    }
    return PageView.builder(
      key: ValueKey('carosello-$_soloMie-$_filtroStato'),
      controller: _carosello,
      itemCount: visibili.length,
      onPageChanged: (i) => _seleziona(visibili[i]['id'], muoviCarosello: false),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: KeyedSubtree(
            key: ValueKey('riga-${visibili[i]['id']}'),
            child: _riga(visibili[i], scelta: visibili[i]['id'] == _selezionata),
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
    final mostraNota = !_caricamento && _errore == null && _items.isNotEmpty && conPosizione.isEmpty && !_soloMie;
    // Altezza delle schede: segue la dimensione del testo scelta sul telefono.
    final altezzaSchede = 40 + MediaQuery.textScalerOf(context).scale(66);

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
        if (mostraNota)
          Positioned(
            top: _altezzaFiltri + 2,
            left: margineLaterale,
            right: margineLaterale,
            child: Align(alignment: Alignment.topLeft, child: _notaPrivacy(s)),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_caricamento && _errore == null && _visibili.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(margineLaterale, 0, margineLaterale, 10),
                      child: _pulsanteElenco(s, _visibili.length),
                    ),
                  SizedBox(
                    height: altezzaSchede,
                    child: _caroselloSchede(s),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
