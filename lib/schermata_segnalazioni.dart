import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'citizen_api.dart';
import 'mappa_parco.dart';
import 'ui.dart';

/// Scorrimento del carosello che si ferma subito. Con la molla predefinita la
/// scheda impiega quasi un secondo ad assestarsi e nell'ultimo tratto sembra
/// ferma ma si muove ancora: un tocco allora ferma lo scorrimento invece di
/// aprire la scheda. Qui la molla è più rigida e lo scorrimento finisce appena
/// mancano pochi decimi di pixel.
class SchedeRapide extends ScrollPhysics {
  const SchedeRapide({super.parent});

  @override
  SchedeRapide applyTo(ScrollPhysics? ancestor) => SchedeRapide(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(mass: .5, stiffness: 420, ratio: 1);

  @override
  Tolerance toleranceFor(ScrollMetrics metrics) => const Tolerance(velocity: 30, distance: .3);
}

/// Ordina gli elementi seguendo la loro posizione, così due vicini nel
/// carosello sono vicini anche sulla mappa: si parte da un'estremità del lato
/// più lungo (ovest o nord) e si va ogni volta al più vicino non ancora preso.
/// Quelli senza posizione restano in fondo, nell'ordine di prima.
List<T> ordinaPerVicinanza<T>(List<T> elementi, LatLng? Function(T) posizione) {
  final punti = <(T, double, double)>[];
  final senza = <T>[];
  for (final e in elementi) {
    final p = posizione(e);
    if (p == null) {
      senza.add(e);
    } else {
      // Gradi di longitudine accorciati verso i poli: distanze quasi in metri.
      punti.add((e, p.longitude * math.cos(p.latitude * math.pi / 180), p.latitude));
    }
  }
  if (punti.length < 3) {
    punti.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final p in punti) p.$1, ...senza];
  }
  final xs = punti.map((p) => p.$2);
  final ys = punti.map((p) => p.$3);
  final largo = xs.reduce(math.max) - xs.reduce(math.min) >= ys.reduce(math.max) - ys.reduce(math.min);
  var corrente = 0;
  for (var i = 1; i < punti.length; i++) {
    final migliore = largo ? punti[i].$2 < punti[corrente].$2 : punti[i].$3 > punti[corrente].$3;
    if (migliore) corrente = i;
  }
  final restanti = [...punti];
  final ordinati = <T>[];
  var ultimo = restanti.removeAt(corrente);
  ordinati.add(ultimo.$1);
  while (restanti.isNotEmpty) {
    var vicino = 0;
    var distanza = double.infinity;
    for (var i = 0; i < restanti.length; i++) {
      final dx = restanti[i].$2 - ultimo.$2;
      final dy = restanti[i].$3 - ultimo.$3;
      final d = dx * dx + dy * dy;
      if (d < distanza) {
        distanza = d;
        vicino = i;
      }
    }
    ultimo = restanti.removeAt(vicino);
    ordinati.add(ultimo.$1);
  }
  return [...ordinati, ...senza];
}

/// Mappa delle segnalazioni del parco.
///
/// La mappa occupa tutta la pagina; sopra ci sono i filtri, sotto un carosello
/// di schede nell'ordine dei segnaposto e un pulsante che apre l'elenco completo.
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

  /// Vero mentre il carosello si muove da solo (tocco sulla mappa o sull'elenco):
  /// le schede che attraversa non diventano la scelta e la mappa resta ferma.
  bool _caroselloGuidato = false;
  int _mossaCarosello = 0;

  /// Dissolvenza dei salti lunghi: la scheda lontana compare senza far
  /// scorrere tutte quelle in mezzo.
  late final AnimationController _dissolvenza = AnimationController(vsync: this, value: 1);

  /// Ordine del carosello per [_items] e [_filtroStato] (si ricalcola solo se cambiano).
  List<Map<String, dynamic>>? _ordine;
  List<Map<String, dynamic>>? _ordineDi;
  String? _ordineFiltro;

  /// Spazio occupato in alto dalla barra dei filtri.
  static const double _altezzaFiltri = 58;
  /// Altezza delle schede: segue la dimensione del testo scelta sul telefono.
  double get _altezzaSchede => 40 + MediaQuery.textScalerOf(context).scale(66);

  /// Spazio occupato in basso da carosello e pulsante dell'elenco
  /// (margine 12, schede, spazio 10, pulsante 38, e un po' d'aria).
  double get _ingombroBasso => 12 + _altezzaSchede + 10 + 38 + 4;

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
    _dissolvenza.dispose();
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
        _allineaCarosello();
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
    final foglio = _ingombroBasso;
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

  /// Schede del carosello nell'ordine dei segnaposto sulla mappa.
  List<Map<String, dynamic>> get _ordineCarosello {
    if (_ordine == null || !identical(_ordineDi, _items) || _ordineFiltro != _filtroStato) {
      _ordine = ordinaPerVicinanza(_visibili, MappaParco.puntoDi);
      _ordineDi = _items;
      _ordineFiltro = _filtroStato;
    }
    return _ordine!;
  }

  /// Porta il carosello alla scheda [indice] senza che le schede attraversate
  /// diventino la scelta: quella accanto scorre, una lontana compare in dissolvenza.
  Future<void> _portaCaroselloA(int indice) async {
    if (!_carosello.hasClients) return;
    final attuale = _carosello.page?.round() ?? 0;
    if (attuale == indice) return;
    final mossa = ++_mossaCarosello;
    _caroselloGuidato = true;
    try {
      final d = durata(context, 220);
      if (d == Duration.zero) {
        _carosello.jumpToPage(indice);
      } else if ((indice - attuale).abs() == 1) {
        await _carosello.animateToPage(indice, duration: d, curve: Curves.easeOutCubic);
      } else {
        await _dissolvenza.animateTo(0, duration: const Duration(milliseconds: 90));
        if (!mounted || mossa != _mossaCarosello || !_carosello.hasClients) return;
        _carosello.jumpToPage(indice);
        await _dissolvenza.animateTo(1, duration: const Duration(milliseconds: 180));
      }
    } finally {
      if (mossa == _mossaCarosello) {
        _caroselloGuidato = false;
        if (mounted && _dissolvenza.value < 1) _dissolvenza.value = 1;
      }
    }
  }

  /// Dopo una ricarica o un filtro il carosello torna sulla scheda scelta.
  void _allineaCarosello() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selezionata == null) return;
      final indice = _ordineCarosello.indexWhere((r) => r['id'] == _selezionata);
      if (indice < 0 || !_carosello.hasClients || _carosello.page?.round() == indice) return;
      final mossa = ++_mossaCarosello;
      _caroselloGuidato = true;
      _carosello.jumpToPage(indice);
      if (mossa == _mossaCarosello) _caroselloGuidato = false;
    });
  }

  /// Sceglie una segnalazione: il carosello va alla sua scheda (se la scelta
  /// non arriva proprio dal carosello) e la mappa mostra il suo segnaposto.
  void _seleziona(Object? id, {bool avvicina = false, bool muoviCarosello = true}) {
    setState(() => _selezionata = id);
    if (id == null) return;
    final indice = _ordineCarosello.indexWhere((r) => r['id'] == id);
    if (muoviCarosello && indice >= 0) unawaited(_portaCaroselloA(indice));
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
      padding: EdgeInsets.fromLTRB(56, _altezzaFiltri + 40, 56, _ingombroBasso + 40),
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
                      onPressed: onChiudi,
                      icon: Icon(Icons.close_rounded, color: testoSecondario),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      CronologiaStato(stato: _statoDi(r), s: s),
                      if (testoDescr.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(testoDescr, style: TextStyle(fontSize: 14.5, color: testo, height: 1.45)),
                      ],
                      if (rating is int && rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(children: List.generate(rating, (_) => Icon(Icons.star_rounded, size: 18, color: sole))),
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
                Icon(icona, size: 17, color: attiva ? suAccento : testoSecondario),
                const SizedBox(width: 5),
                Text(
                  testoVoce,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: attiva ? suAccento : testoSecondario,
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
      onSelected: (v) {
        setState(() {
          _filtroStato = v.isEmpty ? null : v;
          if (_selezionata != null && !_visibili.any((r) => r['id'] == _selezionata)) _selezionata = null;
        });
        _allineaCarosello();
      },
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
              if (scelto != null) ...[puntino(suAccento), const SizedBox(width: 6)],
              Text(
                etichetta,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: scelto == null ? testo : suAccento),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: scelto == null ? testoSecondario : suAccento),
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
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, .88, 1],
        ).createShader(r),
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
      ),
    );
  }

  /// Riporta la mappa a inquadrare tutte le segnalazioni visibili.
  void _ricentra(List<(Map<String, dynamic>, LatLng)> punti) {
    final MapCamera cam;
    try {
      cam = _mappa.camera;
    } catch (_) {
      return;
    }
    if (punti.isEmpty) {
      _volo.vola(MappaParco.centroParco(), 16, animato: _animazioni);
      return;
    }
    final adatta = CameraFit.coordinates(
      coordinates: [for (final e in punti) e.$2],
      padding: EdgeInsets.fromLTRB(48, _altezzaFiltri + 40, 48, _ingombroBasso + 30),
      maxZoom: 17,
    ).fit(cam);
    _volo.vola(adatta.center, adatta.zoom, animato: _animazioni);
  }

  Widget _pulsanteRicentra(Copie s, List<(Map<String, dynamic>, LatLng)> punti) => Material(
        color: superficie,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: .3),
        child: IconButton(
          tooltip: s.t('Mostra tutte le segnalazioni', 'Show all reports'),
          onPressed: () {
            HapticFeedback.selectionClick();
            _ricentra(punti);
          },
          icon: Icon(Icons.center_focus_strong_rounded, color: cieloScuro),
        ),
      );

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
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.2),
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
                Icon(Icons.view_list_rounded, size: 18, color: cieloScuro),
                const SizedBox(width: 6),
                Text(
                  totale == 1 ? s.t('1 segnalazione', '1 report') : s.t('$totale segnalazioni', '$totale reports'),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: testo),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_less_rounded, size: 18, color: testoSecondario),
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
                Icon(Icons.lock_outline_rounded, size: 16, color: testoSecondario),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: s.t('Le posizioni degli altri sono private · ', 'Others’ locations are private · ')),
                      TextSpan(
                        text: s.t('Vedi le mie', 'See mine'),
                        style: TextStyle(color: foresta, fontWeight: FontWeight.w800),
                      ),
                    ]),
                    style: TextStyle(fontSize: 12.5, color: testoSecondario, fontWeight: FontWeight.w600),
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
          Text(s.t('Caricamento delle segnalazioni…', 'Loading reports…'), style: TextStyle(color: testoSecondario)),
        ]),
      ));
    }
    if (_errore != null) {
      return unica(Scheda(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, color: coralloScuro),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_errore!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: testo)),
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
          Icon(Icons.inbox_outlined, color: testoSecondario),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _filtroStato != null
                  ? s.t('Nessuna segnalazione con questo stato.', 'No reports with this status.')
                  : _soloMie
                      ? s.t('Non hai ancora inviato segnalazioni.', 'You have not sent any reports yet.')
                      : s.t('Nessuna segnalazione.', 'No reports.'),
              style: TextStyle(fontSize: 14, color: testoSecondario),
            ),
          ),
        ]),
      ));
    }
    final ordine = _ordineCarosello;
    return FadeTransition(
      opacity: _dissolvenza,
      child: PageView.builder(
      key: ValueKey('carosello-$_soloMie-$_filtroStato'),
      controller: _carosello,
      // Sopra il comportamento della piattaforma (bordi fermi su Android).
      physics: const SchedeRapide().applyTo(ScrollConfiguration.of(context).getScrollPhysics(context)),
      itemCount: ordine.length,
      // Le schede attraversate mentre il carosello si muove da solo non contano.
      onPageChanged: (i) {
        if (!_caroselloGuidato) _seleziona(ordine[i]['id'], muoviCarosello: false);
      },
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: KeyedSubtree(
            key: ValueKey('riga-${ordine[i]['id']}'),
            child: _riga(ordine[i], scelta: ordine[i]['id'] == _selezionata),
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
    final mostraNota = !_caricamento && _errore == null && _items.isNotEmpty && conPosizione.isEmpty && !_soloMie;
    final altezzaSchede = _altezzaSchede;

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
              chiave: (r) => r['id'],
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
        Positioned(right: 12, top: _altezzaFiltri + 30, child: _pulsanteRicentra(s, conPosizione)),
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

/// Avanzamento di una segnalazione: Ricevuta → In corso → Risolta (o Chiusa).
/// La linea si riempie fino allo stato attuale.
class CronologiaStato extends StatelessWidget {
  final String stato;
  final Copie s;
  const CronologiaStato({super.key, required this.stato, required this.s});

  @override
  Widget build(BuildContext context) {
    final chiusa = stato == 'closed';
    final passi = [
      ('received', s.t('Ricevuta', 'Received'), Icons.inbox_rounded),
      ('in_progress', s.t('In corso', 'In progress'), Icons.construction_rounded),
      chiusa
          ? ('closed', s.t('Chiusa', 'Closed'), Icons.lock_rounded)
          : ('resolved', s.t('Risolta', 'Resolved'), Icons.check_rounded),
    ];
    final attuale = switch (stato) {
      'in_progress' => 1,
      'resolved' || 'closed' => 2,
      _ => 0,
    };
    final colore = coloreStatoSegnalazione(stato);
    return Semantics(
      label: s.t('Stato: ${passi[attuale].$2}', 'Status: ${passi[attuale].$2}'),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: attuale / 2),
        duration: durata(context, 700),
        curve: Curves.easeInOutCubic,
        builder: (context, avanzamento, _) => LayoutBuilder(
          builder: (context, vincoli) {
            const d = 26.0;
            final tratto = vincoli.maxWidth - d;
            return Column(
              children: [
                SizedBox(
                  height: d,
                  child: Stack(
                    children: [
                      Positioned(
                        left: d / 2,
                        right: d / 2,
                        top: d / 2 - 2,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: bordo, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      Positioned(
                        left: d / 2,
                        top: d / 2 - 2,
                        height: 4,
                        width: tratto * avanzamento,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: colore, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      for (final (i, passo) in passi.indexed)
                        Positioned(
                          left: tratto * i / 2,
                          child: AnimatedContainer(
                            duration: durata(context, 300),
                            width: d,
                            height: d,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: avanzamento * 2 >= i - .01 ? colore : superficie,
                              border: Border.all(color: avanzamento * 2 >= i - .01 ? colore : bordoForte, width: 2),
                            ),
                            child: Icon(
                              passo.$3,
                              size: 14,
                              color: avanzamento * 2 >= i - .01 ? Colors.white : testoTenue,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (final (i, passo) in passi.indexed)
                      Expanded(
                        child: Text(
                          passo.$2,
                          textAlign: i == 0 ? TextAlign.start : i == 1 ? TextAlign.center : TextAlign.end,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: i == attuale ? FontWeight.w800 : FontWeight.w600,
                            color: i == attuale ? colore : testoSecondario,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
