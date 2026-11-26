import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ui.dart';

/// Una voce della barra in basso.
class VoceBarra {
  final IconData icona;
  final IconData iconaScelta;
  final String etichetta;
  final Accento accento;

  const VoceBarra({
    required this.icona,
    required this.iconaScelta,
    required this.etichetta,
    required this.accento,
  });
}

/// Durata del cambio scheda, uguale per la barra e per le pagine: cresce un
/// poco con la distanza, così un salto lungo non sembra uno scatto.
Duration durataCambioScheda(BuildContext context, num distanza) =>
    durata(context, (280 + 40 * (distanza.abs() - 1)).clamp(280, 420).round());

/// Curva unica del cambio scheda (barra e pagine).
const Curve curvaCambioScheda = Curves.easeOutCubic;

/// Barra di navigazione in basso con un solo indicatore che scivola da una
/// voce all'altra.
///
/// Tutto ciò che cambia dipende dallo stesso valore animato: l'indicatore
/// scivola e cambia colore insieme, e una voce si colora (icona piena) solo
/// quando l'indicatore le è sopra: il colore non arriva mai prima del
/// movimento. Se si tocca un'altra voce a metà corsa l'animazione riparte da
/// dove si trova, senza salti.
class BarraSchede extends StatefulWidget {
  final List<VoceBarra> voci;
  final int indice;
  final ValueChanged<int> onScelta;

  const BarraSchede({super.key, required this.voci, required this.indice, required this.onScelta});

  static const double altezza = 68;
  static const double larghezzaIndicatore = 58, altezzaIndicatore = 32;
  /// Spazio sopra l'icona: l'indicatore sta esattamente dietro l'icona.
  static const double margineAlto = 9;
  static const Key chiaveIndicatore = ValueKey('indicatore-barra');

  @override
  State<BarraSchede> createState() => _BarraSchedeState();
}

class _BarraSchedeState extends State<BarraSchede> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, value: 1);
  late final Animation<double> _t = _anim.drive(CurveTween(curve: curvaCambioScheda));

  // Stato visibile all'inizio dello spostamento in corso; la destinazione è widget.indice.
  late double _posizioneDa = widget.indice.toDouble();
  late List<double> _accensioneDa = _soloAccesa(widget.indice);
  late Color _coloreDa = widget.voci[widget.indice].accento.tinta;

  List<double> _soloAccesa(int indice) => [for (var i = 0; i < widget.voci.length; i++) i == indice ? 1.0 : 0.0];

  double _posizione(int verso, double t) => lerpDouble(_posizioneDa, verso.toDouble(), t)!;
  Color _colore(List<VoceBarra> voci, int verso, double t) => Color.lerp(_coloreDa, voci[verso].accento.tinta, t)!;

  /// Quanto l'indicatore copre la voce [i]: 1 sopra, 0 a una voce o più di distanza.
  static double _vicinanza(double posizione, int i) => (1 - (posizione - i).abs()).clamp(0.0, 1.0);

  /// Quanto è accesa (colorata, icona piena) la voce [i]. Mai più di quanto
  /// l'indicatore le sia vicino: la destinazione si colora solo quando
  /// l'indicatore arriva, la partenza si spegne mentre se ne va e le voci
  /// attraversate lungo un salto lungo restano grigie.
  double _accensione(int i, int verso, double t, double posizione) {
    final vicino = _vicinanza(posizione, i);
    return i == verso
        ? math.min(vicino, lerpDouble(_accensioneDa[i], 1, t)!)
        : math.min(_accensioneDa[i], vicino);
  }

  @override
  void didUpdateWidget(BarraSchede vecchia) {
    super.didUpdateWidget(vecchia);
    if (vecchia.indice == widget.indice) return;
    // Si parte da ciò che si vede adesso (anche a metà di un altro spostamento).
    final t = _t.value;
    final posizione = _posizione(vecchia.indice, t);
    _accensioneDa = [for (var i = 0; i < widget.voci.length; i++) _accensione(i, vecchia.indice, t, posizione)];
    _coloreDa = _colore(vecchia.voci, vecchia.indice, t);
    _posizioneDa = posizione;
    final d = durataCambioScheda(context, widget.indice - posizione);
    if (d == Duration.zero) {
      _anim.value = 1;
    } else {
      _anim.duration = d;
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _voce(int i, double accesa) {
    final v = widget.voci[i];
    final colore = Color.lerp(testoSecondario, v.accento.forte, accesa)!;
    final stessaIcona = v.icona == v.iconaScelta;
    return MergeSemantics(
      child: Semantics(
        selected: i == widget.indice,
        button: true,
        child: InkWell(
          onTap: () => widget.onScelta(i),
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(18),
          // L'indicatore che scivola è già il riscontro al tocco: niente
          // increspature né alone al passaggio del mouse (sembrerebbe un colore
          // arrivato prima dell'indicatore). Solo l'alone del focus da tastiera.
          overlayColor: WidgetStateProperty.resolveWith(
            (stati) => stati.contains(WidgetState.focused) ? v.accento.tinta.withValues(alpha: .6) : Colors.transparent,
          ),
          child: Premibile(
            scala: .92,
            child: Column(
              children: [
                const SizedBox(height: BarraSchede.margineAlto),
                SizedBox(
                  height: BarraSchede.altezzaIndicatore,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + .08 * accesa,
                      child: stessaIcona
                          ? Icon(v.icona, size: 24, color: colore)
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                // L'icona vuota sfuma in quella piena insieme al colore.
                                Opacity(opacity: 1 - accesa, child: Icon(v.icona, size: 24, color: colore)),
                                Opacity(opacity: accesa, child: Icon(v.iconaScelta, size: 24, color: colore)),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v.etichetta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Peso costante: cambiarlo farebbe ballare la larghezza delle etichette.
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colore, letterSpacing: .1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x0F12261B), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: Material(
        color: superficie,
        shape: Border(top: BorderSide(color: bordo)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: BarraSchede.altezza,
            child: LayoutBuilder(
              builder: (context, vincoli) {
                final larghezzaVoce = vincoli.maxWidth / widget.voci.length;
                return AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) {
                    final t = _t.value;
                    final verso = widget.indice;
                    final posizione = _posizione(verso, t);
                    // L'indicatore si allunga un poco a metà corsa e torna compatto all'arrivo.
                    final inViaggio = (verso - _posizioneDa).abs() > .01;
                    final larghezza = BarraSchede.larghezzaIndicatore + (inViaggio ? 14 * math.sin(math.pi * t) : 0);
                    return Stack(
                      children: [
                        Positioned(
                          left: posizione * larghezzaVoce + (larghezzaVoce - larghezza) / 2,
                          top: BarraSchede.margineAlto,
                          width: larghezza,
                          height: BarraSchede.altezzaIndicatore,
                          child: DecoratedBox(
                            key: BarraSchede.chiaveIndicatore,
                            decoration: BoxDecoration(
                              color: _colore(widget.voci, verso, t),
                              borderRadius: BorderRadius.circular(BarraSchede.altezzaIndicatore / 2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < widget.voci.length; i++)
                              Expanded(child: _voce(i, _accensione(i, verso, t, posizione))),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
