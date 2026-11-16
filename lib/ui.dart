import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// Un verde foresta come colore dell'app, più quattro accenti caldi e freddi
// che danno a ogni sezione la sua identità. Le varianti "Scuro" servono per
// i testi su fondo chiaro, le "Chiaro" per gli sfondi tenui.
// ─────────────────────────────────────────────────────────────────────────────

const Color foresta = Color(0xFF17694A);
const Color forestaScura = Color(0xFF0E4532);
const Color foglia = Color(0xFF2FA36B);
const Color menta = Color(0xFFE2F3E9);

const Color sole = Color(0xFFF0A202);
const Color soleScuro = Color(0xFF8F5B00);
const Color soleChiaro = Color(0xFFFFF2D2);

const Color cielo = Color(0xFF2C7BE5);
const Color cieloScuro = Color(0xFF1A5AAE);
const Color cieloChiaro = Color(0xFFE5EFFC);

const Color corallo = Color(0xFFE4572E);
const Color coralloScuro = Color(0xFFB42318);
const Color coralloChiaro = Color(0xFFFDEBE6);

const Color lavanda = Color(0xFF6E52D4);
const Color lavandaChiaro = Color(0xFFEEEAFB);

const Color sfondo = Color(0xFFF4F6F1);
const Color superficie = Color(0xFFFFFFFF);
const Color testo = Color(0xFF14231A);
const Color testoSecondario = Color(0xFF5B6B60);
const Color testoTenue = Color(0xFF8A988E);
const Color bordo = Color(0xFFE1E8DD);
const Color bordoForte = Color(0xFFC9D6C6);

/// Terna di colori di un accento: [base] per decorazioni, [forte] per testi e
/// icone su fondo chiaro, [tinta] per gli sfondi tenui.
class Accento {
  final Color base;
  final Color forte;
  final Color tinta;
  const Accento(this.base, this.forte, this.tinta);

  static const verde = Accento(foglia, foresta, menta);
  static const arancio = Accento(corallo, coralloScuro, coralloChiaro);
  static const blu = Accento(cielo, cieloScuro, cieloChiaro);
  static const giallo = Accento(sole, soleScuro, soleChiaro);
  static const viola = Accento(lavanda, lavanda, lavandaChiaro);
}

/// Durata delle animazioni, azzerata se l'utente le disattiva.
Duration durata(BuildContext context, [int ms = 280]) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : Duration(milliseconds: ms);

class Copie {
  final bool inglese;
  const Copie(this.inglese);

  String t(String italiano, String english) => inglese ? english : italiano;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tema
// ─────────────────────────────────────────────────────────────────────────────

ThemeData temaTryees() {
  final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  OutlineInputBorder campo(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    colorScheme: ColorScheme.fromSeed(
      seedColor: foresta,
      primary: foresta,
      secondary: foglia,
      surface: superficie,
      error: coralloScuro,
    ),
    textTheme: ThemeData.light().textTheme.apply(bodyColor: testo, displayColor: testo),
    scaffoldBackgroundColor: sfondo,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: sfondo,
      surfaceTintColor: Colors.transparent,
      foregroundColor: testo,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: menta,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: forma,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        foregroundColor: foresta,
        side: const BorderSide(color: bordoForte, width: 1.4),
        shape: forma,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foresta,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: superficie,
        foregroundColor: testoSecondario,
        selectedBackgroundColor: foresta,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: bordo, width: 1.2),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: superficie,
      selectedColor: menta,
      side: const BorderSide(color: bordo),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: testo),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    cardTheme: const CardThemeData(color: superficie, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(
      backgroundColor: superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: superficie,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: forestaScura,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: foresta),
    dividerTheme: const DividerThemeData(color: bordo, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(fontSize: 14, color: testoSecondario),
      hintStyle: const TextStyle(fontSize: 14, color: testoTenue),
      border: campo(bordoForte, 1.2),
      enabledBorder: campo(bordoForte, 1.2),
      focusedBorder: campo(foresta, 2),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Componenti condivisi
// ─────────────────────────────────────────────────────────────────────────────

class ContenitorePagina extends StatelessWidget {
  final Widget child;
  const ContenitorePagina({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(
                constraints.maxWidth < 380 ? 16 : 20,
                4,
                constraints.maxWidth < 380 ? 16 : 20,
                32,
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Fa comparire il contenuto con dissolvenza e un breve scivolamento verso l'alto.
/// [indice] ritarda leggermente gli elementi successivi per un effetto a cascata.
class Appare extends StatelessWidget {
  final Widget child;
  final int indice;
  const Appare({super.key, required this.child, this.indice = 0});

  @override
  Widget build(BuildContext context) {
    final ms = 380 + (indice.clamp(0, 6) * 70);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: durata(context, ms),
      curve: Curves.easeOutCubic,
      builder: (context, v, figlio) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: figlio),
      ),
      child: child,
    );
  }
}

/// Intestazione di pagina: icona colorata della sezione, titolo e sottotitolo.
class TitoloPagina extends StatelessWidget {
  final String titolo;
  final String descrizione;
  final IconData? icona;
  final Accento accento;

  const TitoloPagina({
    super.key,
    required this.titolo,
    required this.descrizione,
    this.icona,
    this.accento = Accento.verde,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 20),
        child: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icona != null) ...[
                ExcludeSemantics(
                  child: IconaTonda(icona!, colore: accento.forte, sfondo: accento.tinta, dimensione: 44),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                titolo,
                style: const TextStyle(
                  color: testo,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                descrizione,
                style: const TextStyle(fontSize: 15, height: 1.45, color: testoSecondario),
              ),
            ],
          ),
        ),
      );
}

/// Titolo di sezione con contatore opzionale a destra.
class TitoloSezione extends StatelessWidget {
  final String titolo;
  final String? dettaglio;
  final Accento accento;
  const TitoloSezione(this.titolo, {super.key, this.dettaglio, this.accento = Accento.verde});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  titolo,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.2),
                ),
              ),
            ),
            if (dettaglio != null) Etichetta(dettaglio!, colore: accento.forte, sfondo: accento.tinta),
          ],
        ),
      );
}

/// Quadrato arrotondato colorato con icona.
class IconaTonda extends StatelessWidget {
  final IconData icona;
  final Color colore;
  final Color? sfondo;
  final double dimensione;
  const IconaTonda(this.icona, {super.key, this.colore = foresta, this.sfondo, this.dimensione = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: dimensione,
        height: dimensione,
        decoration: BoxDecoration(
          color: sfondo ?? colore.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(dimensione * .32),
        ),
        child: Icon(icona, color: colore, size: dimensione * .52),
      );
}

/// Scheda bianca con bordo morbido e ombra leggera.
/// Il colore è su un [Material], così l'effetto al tocco resta visibile.
class Scheda extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color colore;
  final Color? coloreBordo;
  final VoidCallback? onTap;

  const Scheda({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.colore = superficie,
    this.coloreBordo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final alta = MediaQuery.highContrastOf(context);
    final raggio = BorderRadius.circular(22);
    final contenuto = Padding(padding: padding, child: child);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: raggio,
        boxShadow: const [
          BoxShadow(color: Color(0x0D12261B), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Material(
        color: colore,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: raggio,
          side: BorderSide(
            color: alta ? Colors.black : coloreBordo ?? bordo,
            width: alta ? 1.5 : 1,
          ),
        ),
        child: onTap == null ? contenuto : InkWell(onTap: onTap, child: contenuto),
      ),
    );
  }
}

/// Piccola etichetta a pillola, con puntino o icona opzionali.
class Etichetta extends StatelessWidget {
  final String testo;
  final Color colore;
  final Color? sfondo;
  final IconData? icona;
  final bool puntino;

  const Etichetta(
    this.testo, {
    super.key,
    this.colore = foresta,
    this.sfondo,
    this.icona,
    this.puntino = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sfondo ?? colore.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (puntino) ...[
              Container(width: 7, height: 7, decoration: BoxDecoration(color: colore, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            if (icona != null) ...[
              Icon(icona, size: 14, color: colore),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                testo,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: colore, letterSpacing: .1),
              ),
            ),
          ],
        ),
      );
}

/// Riquadro informativo con icona, per note, avvisi o errori.
class Riquadro extends StatelessWidget {
  final IconData icona;
  final String messaggio;
  final Accento accento;

  const Riquadro({super.key, required this.icona, required this.messaggio, this.accento = Accento.verde});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accento.tinta,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accento.base.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icona, color: accento.forte, size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Text(messaggio, style: const TextStyle(fontSize: 13.5, height: 1.45, color: testo)),
            ),
          ],
        ),
      );
}

/// Stato vuoto o di errore, con un'azione opzionale per riprovare.
class StatoVuoto extends StatelessWidget {
  final IconData icona;
  final String messaggio;
  final Accento accento;
  final VoidCallback? onAzione;
  final String? etichettaAzione;

  const StatoVuoto({
    super.key,
    required this.icona,
    required this.messaggio,
    this.accento = Accento.verde,
    this.onAzione,
    this.etichettaAzione,
  });

  @override
  Widget build(BuildContext context) => Scheda(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            ExcludeSemantics(child: IconaTonda(icona, colore: accento.forte, sfondo: accento.tinta, dimensione: 58)),
            const SizedBox(height: 14),
            Text(
              messaggio,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: testoSecondario),
            ),
            if (onAzione != null && etichettaAzione != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: onAzione,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(etichettaAzione!),
              ),
            ],
          ],
        ),
      );
}

/// Segnaposto animato mostrato mentre un elenco si carica.
class CaricamentoScheletro extends StatefulWidget {
  final int numero;
  final String etichetta;
  const CaricamentoScheletro({super.key, this.numero = 3, required this.etichetta});

  @override
  State<CaricamentoScheletro> createState() => _CaricamentoScheletroState();
}

class _CaricamentoScheletroState extends State<CaricamentoScheletro> with SingleTickerProviderStateMixin {
  late final AnimationController _pulsazione = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulsazione.value = 1;
    } else if (!_pulsazione.isAnimating) {
      _pulsazione.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulsazione.dispose();
    super.dispose();
  }

  Widget _barra(double larghezza, [double altezza = 12]) => FractionallySizedBox(
        widthFactor: larghezza,
        alignment: Alignment.centerLeft,
        child: Container(
          height: altezza,
          decoration: BoxDecoration(color: const Color(0xFFE6ECE3), borderRadius: BorderRadius.circular(8)),
        ),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.etichetta,
        child: ExcludeSemantics(
          child: FadeTransition(
            opacity: Tween<double>(begin: .45, end: 1).animate(_pulsazione),
            child: Column(
              children: List.generate(
                widget.numero,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Scheda(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: const Color(0xFFE6ECE3), borderRadius: BorderRadius.circular(13)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _barra(i.isEven ? .7 : .5, 14)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _barra(1),
                        const SizedBox(height: 8),
                        _barra(.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class PulsanteAzione extends StatelessWidget {
  final String testo;
  final IconData icona;
  final Color colore;
  final VoidCallback? onPressed;
  final bool outlined;

  const PulsanteAzione({
    super.key,
    required this.testo,
    required this.icona,
    this.colore = foresta,
    this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final contenuto = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icona, size: 20),
        const SizedBox(width: 9),
        Flexible(child: Text(testo, textAlign: TextAlign.center)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colore,
                side: BorderSide(color: colore, width: 1.5),
              ),
              onPressed: onPressed,
              child: contenuto,
            )
          : FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colore, foregroundColor: Colors.white),
              onPressed: onPressed,
              child: contenuto,
            ),
    );
  }
}

/// Formatta una data ISO come "gg/mm" (o "gg/mm hh:mm" con [ora]).
String formattaData(dynamic iso, {bool ora = false}) {
  final d = iso is DateTime ? iso : DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  String due(int n) => n.toString().padLeft(2, '0');
  final giorno = '${due(d.day)}/${due(d.month)}';
  return ora ? '$giorno ${due(d.hour)}:${due(d.minute)}' : giorno;
}
