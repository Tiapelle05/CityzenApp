import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'citizen_api.dart';
import 'ui.dart';

export 'package:flutter_map/flutter_map.dart' show Marker;
export 'package:latlong2/latlong.dart' show LatLng;

/// Mappa reale (tile OpenStreetMap) con angoli arrotondati.
class MappaParco extends StatelessWidget {
  final LatLng centro;
  final double zoom;
  final List<Marker> marcatori;
  final double altezza;
  final bool interattiva;
  final void Function(LatLng punto)? onTocco;

  const MappaParco({
    super.key,
    required this.centro,
    this.zoom = 16,
    this.marcatori = const [],
    this.altezza = 420,
    this.interattiva = true,
    this.onTocco,
  });

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
    return Container(
      height: altezza,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: menta,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: bordo),
      ),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: centro,
          initialZoom: zoom,
          minZoom: 13,
          maxZoom: 19,
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
          ),
          MarkerLayer(markers: marcatori),
          const _Attribuzione(),
        ],
      ),
    );
  }
}

class _Attribuzione extends StatelessWidget {
  const _Attribuzione();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(6)),
        child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10, color: testoSecondario)),
      ),
    );
  }
}

/// Segnaposto rotondo con icona, nel colore indicato.
class Segnaposto extends StatelessWidget {
  final IconData icona;
  final Color colore;
  final bool selezionato;

  const Segnaposto({super.key, required this.icona, required this.colore, this.selezionato = false});

  static const double dimensione = 46;

  @override
  Widget build(BuildContext context) {
    final lato = selezionato ? 42.0 : 34.0;
    return Center(
      child: AnimatedContainer(
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
        child: Icon(icona, color: Colors.white, size: selezionato ? 22 : 18),
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

  const AnteprimaMappa({super.key, required this.s, this.onApri});

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
                altezza: 230,
                zoom: 15.5,
                interattiva: false,
                centro: MappaParco.centroParco(punti.map((e) => e.$2)),
                marcatori: [
                  for (final (r, p) in punti)
                    Marker(
                      point: p,
                      width: Segnaposto.dimensione,
                      height: Segnaposto.dimensione,
                      child: Segnaposto(
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
                    const Icon(Icons.place_rounded, size: 16, color: cieloScuro),
                    const SizedBox(width: 6),
                    Text(riepilogo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: testo)),
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
