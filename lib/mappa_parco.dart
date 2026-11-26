import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'citizen_api.dart';
import 'ui.dart';

export 'package:flutter_map/flutter_map.dart' show Marker, MapController, MapCamera, CameraFit;
export 'package:latlong2/latlong.dart' show LatLng;

/// Mappa reale (tile OpenStreetMap). Con [altezza] è una scheda ad angoli
/// arrotondati; senza, riempie lo spazio disponibile a filo bordo.
class MappaParco extends StatelessWidget {
  final LatLng centro;
  final double zoom;
  final List<Marker> marcatori;
  /// Livelli aggiuntivi sopra le tile (es. [LivelloGruppi]).
  final List<Widget> livelli;
  final double? altezza;
  final bool interattiva;
  final MapController? controller;
  final EdgeInsets margineAttribuzione;
  final Alignment allineamentoAttribuzione;
  final void Function(LatLng punto)? onTocco;

  const MappaParco({
    super.key,
    required this.centro,
    this.zoom = 16,
    this.marcatori = const [],
    this.livelli = const [],
    this.altezza = 420,
    this.interattiva = true,
    this.controller,
    this.margineAttribuzione = EdgeInsets.zero,
    this.allineamentoAttribuzione = Alignment.bottomRight,
    this.onTocco,
  });

  static const double zoomMassimo = 19;

  /// Centro del parco in uso; se manca, il primo punto disponibile o Milano.
  static LatLng centroParco([Iterable<LatLng> punti = const []]) {
    final p = CitizenApi.instance.park;
    final lat = p?['lat'], lon = p?['lon'];
    if (lat is num && lon is num) return LatLng(lat.toDouble(), lon.toDouble());
    if (punti.isNotEmpty) return punti.first;
    return const LatLng(45.4730, 9.1759);
  }

  /// Coordinate di una segnalazione del backend (campi lat/lon), se presenti.
  static LatLng? puntoDi(Map<String, dynamic> r) {
    final lat = r['lat'], lon = r['lon'];
    return lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : null;
  }

  @override
  Widget build(BuildContext context) {
    final mappa = FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: zoom,
        minZoom: 13,
        maxZoom: zoomMassimo,
        backgroundColor: menta,
        interactionOptions: InteractionOptions(
          flags: interattiva ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
        onTap: onTocco == null ? null : (_, punto) => onTocco!(punto),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'it.tryees.app',
          maxNativeZoom: 19,
          // Al buio la cartina si abbassa di luminosità e perde un po' di saturazione.
          tileBuilder: temaScuro ? (context, tile, _) => ColorFiltered(colorFilter: _filtroNotte, child: tile) : null,
        ),
        if (marcatori.isNotEmpty) MarkerLayer(markers: marcatori),
        ...livelli,
        Padding(padding: margineAttribuzione, child: _Attribuzione(allineamentoAttribuzione)),
      ],
    );
    if (altezza == null) return ColoredBox(color: menta, child: mappa);
    return Container(
      height: altezza,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: menta,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: bordo),
      ),
      child: mappa,
    );
  }
}

/// Matrice che scurisce e desatura le tessere della cartina nel tema scuro.
const ColorFilter _filtroNotte = ColorFilter.matrix(<double>[
  0.45, 0.12, 0.03, 0, 0, //
  0.08, 0.50, 0.03, 0, 0, //
  0.08, 0.12, 0.40, 0, 0, //
  0, 0, 0, 1, 0,
]);

class _Attribuzione extends StatelessWidget {
  final Alignment allineamento;
  const _Attribuzione(this.allineamento);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: allineamento,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: superficie.withValues(alpha: .85), borderRadius: BorderRadius.circular(6)),
        child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10, color: testoSecondario)),
      ),
    );
  }
}

/// Livello che raggruppa i punti troppo vicini sullo schermo in un unico
/// cerchio con il numero di elementi, così ogni segnaposto resta toccabile.
/// Si ricalcola a ogni zoom: avvicinandosi i gruppi si separano.
class LivelloGruppi<T> extends StatelessWidget {
  final List<(T, LatLng)> punti;
  final Widget Function(T dato) segnaposto;
  /// Tocco su un gruppo; se nullo il gruppo è solo decorativo.
  final void Function(List<(T, LatLng)> gruppo)? onGruppo;
  /// Il gruppo contiene l'elemento scelto: lo si evidenzia.
  final bool Function(T dato)? scelto;
  final String Function(int quanti)? etichettaGruppo;

  const LivelloGruppi({
    super.key,
    required this.punti,
    required this.segnaposto,
    this.onGruppo,
    this.scelto,
    this.etichettaGruppo,
  });

  /// Distanza minima in pixel sotto la quale due segnaposto si uniscono.
  static const double soglia = 46;

  /// Raggruppa [punti] allo [zoom] indicato (in pixel della proiezione).
  static List<List<(T, LatLng)>> raggruppa<T>(MapCamera camera, List<(T, LatLng)> punti, double zoom) {
    final membri = <List<(T, LatLng)>>[];
    final somme = <Offset>[];
    for (final p in punti) {
      final px = camera.projectAtZoom(p.$2, zoom);
      var aggiunto = false;
      for (var i = 0; i < membri.length; i++) {
        final centro = somme[i] / membri[i].length.toDouble();
        if ((centro - px).distance < soglia) {
          membri[i].add(p);
          somme[i] += px;
          aggiunto = true;
          break;
        }
      }
      if (!aggiunto) {
        membri.add([p]);
        somme.add(px);
      }
    }
    return membri;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final gruppi = raggruppa(camera, punti, camera.zoom);
    // I gruppi si disegnano sopra i segnaposto singoli; quello scelto in cima.
    int peso(List<(T, LatLng)> g) =>
        (g.length > 1 ? 1 : 0) + (scelto != null && g.any((e) => scelto!(e.$1)) ? 2 : 0);
    gruppi.sort((a, b) => peso(a) - peso(b));

    return MarkerLayer(
      markers: [
        for (final g in gruppi)
          if (g.length == 1)
            Marker(
              point: g.first.$2,
              width: Segnaposto.dimensione,
              height: Segnaposto.dimensione,
              child: segnaposto(g.first.$1),
            )
          else
            Marker(
              point: LatLng(
                g.map((e) => e.$2.latitude).reduce((a, b) => a + b) / g.length,
                g.map((e) => e.$2.longitude).reduce((a, b) => a + b) / g.length,
              ),
              width: 58,
              height: 58,
              child: Semantics(
                button: onGruppo != null,
                label: etichettaGruppo?.call(g.length) ?? '${g.length}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onGruppo == null ? null : () => onGruppo!(g),
                  child: SegnapostoGruppo(
                    quanti: g.length,
                    selezionato: scelto != null && g.any((e) => scelto!(e.$1)),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Cerchio scuro con il numero di segnalazioni raggruppate.
const Color _verdeGruppo = Color(0xFF0E4532);

class SegnapostoGruppo extends StatelessWidget {
  final int quanti;
  final bool selezionato;
  const SegnapostoGruppo({super.key, required this.quanti, this.selezionato = false});

  @override
  Widget build(BuildContext context) {
    final lato = 38 + (quanti - 2).clamp(0, 8) * 1.5;
    return Center(
      child: Container(
        width: lato,
        height: lato,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _verdeGruppo,
          shape: BoxShape.circle,
          border: Border.all(color: selezionato ? sole : Colors.white, width: selezionato ? 4 : 3),
          boxShadow: [
            BoxShadow(color: _verdeGruppo.withValues(alpha: .25), spreadRadius: 5),
            BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Text(
          quanti > 99 ? '99+' : '$quanti',
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

/// Sposta la mappa con un'animazione morbida verso un centro e uno zoom.
class AnimatoreMappa {
  final MapController controller;
  final AnimationController _anim;
  LatLng _da = const LatLng(0, 0), _a = const LatLng(0, 0);
  double _zoomDa = 0, _zoomA = 0;

  AnimatoreMappa(this.controller, TickerProvider vsync)
      : _anim = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 450)) {
    _anim.addListener(() {
      final t = Curves.easeInOutCubic.transform(_anim.value);
      controller.move(
        LatLng(
          _da.latitude + (_a.latitude - _da.latitude) * t,
          _da.longitude + (_a.longitude - _da.longitude) * t,
        ),
        _zoomDa + (_zoomA - _zoomDa) * t,
      );
    });
  }

  void vola(LatLng centro, double zoom, {bool animato = true}) {
    final cam = controller.camera;
    _da = cam.center;
    _zoomDa = cam.zoom;
    _a = centro;
    _zoomA = zoom.clamp(13, MappaParco.zoomMassimo).toDouble();
    if (!animato) {
      _anim.stop();
      controller.move(_a, _zoomA);
      return;
    }
    _anim.forward(from: 0);
  }

  void ferma() => _anim.stop();

  void dispose() => _anim.dispose();
}

/// Segnaposto rotondo con icona, nel colore indicato. Compare con una
/// piccola caduta e, quando è scelto, un anello pulsa attorno.
class Segnaposto extends StatefulWidget {
  final IconData icona;
  final Color colore;
  final bool selezionato;

  const Segnaposto({super.key, required this.icona, required this.colore, this.selezionato = false});

  static const double dimensione = 46;

  @override
  State<Segnaposto> createState() => _SegnapostoState();
}

class _SegnapostoState extends State<Segnaposto> with SingleTickerProviderStateMixin {
  AnimationController? _pulsazione;

  bool get _animazioni => !MediaQuery.of(context).disableAnimations;

  void _aggiornaPulsazione() {
    if (widget.selezionato && _animazioni) {
      (_pulsazione ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))).repeat();
    } else {
      _pulsazione?.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aggiornaPulsazione();
  }

  @override
  void didUpdateWidget(Segnaposto vecchio) {
    super.didUpdateWidget(vecchio);
    if (vecchio.selezionato != widget.selezionato) _aggiornaPulsazione();
  }

  @override
  void dispose() {
    _pulsazione?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selezionato = widget.selezionato;
    // Al buio i colori di stato sono chiari: il segnaposto resta pieno e scuro
    // quanto basta perché l'icona bianca si legga.
    var colore = widget.colore;
    if (temaScuro) {
      final hsl = HSLColor.fromColor(colore);
      if (hsl.lightness > .45) colore = hsl.withLightness(.42).toColor();
    }
    final lato = selezionato ? 42.0 : 34.0;
    final pallino = AnimatedContainer(
      duration: durata(context, 200),
      curve: Curves.easeOutBack,
      width: lato,
      height: lato,
      decoration: BoxDecoration(
        color: colore,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selezionato ? 3.5 : 2.5),
        boxShadow: [
          BoxShadow(color: colore.withValues(alpha: .45), blurRadius: selezionato ? 14 : 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Icon(widget.icona, color: Colors.white, size: selezionato ? 22 : 18),
    );
    final pulsazione = _pulsazione;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: durata(context, 520),
        curve: Curves.elasticOut,
        builder: (context, v, figlio) => Transform.translate(
          offset: Offset(0, -18 * (1 - v.clamp(0, 1))),
          child: Transform.scale(scale: .4 + .6 * v, child: figlio),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (selezionato && pulsazione != null)
              AnimatedBuilder(
                animation: pulsazione,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(pulsazione.value);
                  return Container(
                    width: lato * (1 + t * .9),
                    height: lato * (1 + t * .9),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colore.withValues(alpha: (1 - t) * .7), width: 3),
                    ),
                  );
                },
              ),
            pallino,
          ],
        ),
      ),
    );
  }
}

/// Icona di una categoria dal suo codice backend.
IconData iconaCategoria(String? codice) => switch (codice) {
      'lighting' => Icons.lightbulb_rounded,
      'waste' => Icons.delete_rounded,
      'green' => Icons.park_rounded,
      'irrigation' || 'fountains' => Icons.water_drop_rounded,
      'furniture' => Icons.chair_rounded,
      'cleaning' => Icons.cleaning_services_rounded,
      'safety' => Icons.shield_rounded,
      'play' => Icons.sports_soccer_rounded,
      _ => Icons.place_rounded,
    };

/// Colore di una segnalazione in base al suo stato backend.
Color coloreStatoSegnalazione(String? stato) => switch (stato) {
      'resolved' => foresta,
      'in_progress' => soleScuro,
      'closed' => testoSecondario,
      _ => cieloScuro,
    };

/// Anteprima della mappa per la home: mostra i problemi segnalati,
/// non è interattiva e un tocco apre la mappa completa.
class AnteprimaMappa extends StatefulWidget {
  final Copie s;
  final VoidCallback? onApri;
  final double altezza;

  const AnteprimaMappa({super.key, required this.s, this.onApri, this.altezza = 230});

  @override
  State<AnteprimaMappa> createState() => _AnteprimaMappaState();
}

class _AnteprimaMappaState extends State<AnteprimaMappa> {
  List<Map<String, dynamic>> _items = const [];
  bool _caricata = false;
  StreamSubscription<Map<String, dynamic>>? _live;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_carica());
    CitizenApi.instance.connectLive();
    _live = CitizenApi.instance.events.listen((e) {
      final type = e['type'];
      if (type == 'report_updated' || type == 'report_created' || type == 'report_status_changed') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), _carica);
      }
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _carica() async {
    try {
      final data = await CitizenApi.instance.getFeed(kind: 'problem', limit: 50);
      final rows = (data['items'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _items = rows; _caricata = true; });
    } catch (_) {
      // Senza server la mappa resta visibile, solo senza segnaposti.
      if (mounted) setState(() => _caricata = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final punti = [
      for (final r in _items)
        if (MappaParco.puntoDi(r) case final p?) (r, p),
    ];
    final aperti = _items.where((r) => r['status'] != 'resolved' && r['status'] != 'closed').length;
    final riepilogo = !_caricata
        ? s.t('Caricamento…', 'Loading…')
        : aperti == 0
            ? s.t('Nessun problema aperto', 'No open problems')
            : aperti == 1
                ? s.t('1 problema aperto', '1 open problem')
                : s.t('$aperti problemi aperti', '$aperti open problems');

    return Semantics(
      button: widget.onApri != null,
      label: '${s.t('Mappa del parco', 'Park map')}, $riepilogo',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onApri,
        child: Stack(
          children: [
            AbsorbPointer(
              child: MappaParco(
                altezza: widget.altezza,
                zoom: 15.5,
                interattiva: false,
                centro: MappaParco.centroParco(punti.map((e) => e.$2)),
                livelli: [
                  LivelloGruppi<Map<String, dynamic>>(
                    punti: punti,
                    segnaposto: (r) => Segnaposto(
                      icona: iconaCategoria(r['category'] as String?),
                      colore: coloreStatoSegnalazione(r['status'] as String?),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: superficie,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_rounded, size: 16, color: cieloScuro),
                    const SizedBox(width: 6),
                    Text(riepilogo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: testo)),
                  ],
                ),
              ),
            ),
            if (widget.onApri != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: cieloScuro,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: cieloScuro.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.t('Apri la mappa', 'Open the map'),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 17, color: Colors.white),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
