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
