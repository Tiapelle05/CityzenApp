import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemUiOverlayStyle;

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// Un verde foresta come colore dell'app, più quattro accenti caldi e freddi
// che danno a ogni sezione la sua identità. Le varianti "Scuro" servono per
// i testi (sul tema scuro sono più chiare, per leggersi sul fondo), le
// "Chiaro" per gli sfondi tenui.
// ─────────────────────────────────────────────────────────────────────────────

// I colori sono getter e non costanti: cambiano con il tema chiaro o scuro.
// Il tema attivo si imposta con [impostaTemaScuro]; l'app poi si ricostruisce.

bool _scuro = false;

/// Vero se è attivo il tema scuro.
bool get temaScuro => _scuro;

/// Cambia la tavolozza. Chi la chiama deve poi ricostruire l'app
/// (vedi [ricostruisciTutto]): i colori si rileggono a ogni build.
void impostaTemaScuro(bool scuro) => _scuro = scuro;

Color _t(int chiaro, int scuro) => Color(_scuro ? scuro : chiaro);

Color get foresta => _t(0xFF17694A, 0xFF2E9E6B);
Color get forestaScura => _t(0xFF0E4532, 0xFF8FDDB4);
const Color foglia = Color(0xFF2FA36B);
Color get menta => _t(0xFFE2F3E9, 0xFF183527);

const Color sole = Color(0xFFF0A202);
Color get soleScuro => _t(0xFF8F5B00, 0xFFF5C152);
Color get soleChiaro => _t(0xFFFFF2D2, 0xFF362B10);

const Color cielo = Color(0xFF2C7BE5);
Color get cieloScuro => _t(0xFF1A5AAE, 0xFF5B9BEF);
Color get cieloChiaro => _t(0xFFE5EFFC, 0xFF15263D);

const Color corallo = Color(0xFFE4572E);
Color get coralloScuro => _t(0xFFB42318, 0xFFF0715A);
Color get coralloChiaro => _t(0xFFFDEBE6, 0xFF3A1E17);

Color get lavanda => _t(0xFF6E52D4, 0xFF9C88F2);
Color get lavandaChiaro => _t(0xFFEEEAFB, 0xFF262040);

Color get sfondo => _t(0xFFF4F6F1, 0xFF0E1511);
Color get superficie => _t(0xFFFFFFFF, 0xFF18221C);
/// Superficie leggermente più chiara (scuro) o più scura (chiaro) per i rilievi.
Color get superficieAlta => _t(0xFFF8FAF6, 0xFF212D26);
Color get testo => _t(0xFF14231A, 0xFFE6EEE8);
Color get testoSecondario => _t(0xFF5B6B60, 0xFFA7B6AC);
Color get testoTenue => _t(0xFF8A988E, 0xFF75857B);
Color get bordo => _t(0xFFE1E8DD, 0xFF27342C);
Color get bordoForte => _t(0xFFC9D6C6, 0xFF3B4B41);
/// Ombra delle schede: quasi invisibile al buio, dove contano i bordi.
Color get ombra => _t(0x0D12261B, 0x40000000);

/// Testo e icone sopra un riempimento d'accento (pulsanti pieni, filtri scelti):
/// gli accenti restano di tono medio anche al buio, quindi il bianco si legge sempre.
const Color suAccento = Colors.white;

/// Terna di colori di un accento: [base] per decorazioni, [forte] per testi e
/// icone su fondo chiaro, [tinta] per gli sfondi tenui.
/// Al buio [forte] diventa più luminoso e [tinta] un velo del colore base.
class Accento {
  final Color base;
  final Color _forte;
  final Color _tinta;
  const Accento(this.base, this._forte, this._tinta);

  Color get forte {
    if (!_scuro) return _forte;
    final hsl = HSLColor.fromColor(_forte);
    return hsl.lightness >= .68 ? _forte : hsl.withLightness(.7).toColor();
  }

  Color get tinta => _scuro ? Color.alphaBlend(base.withValues(alpha: .2), superficie) : _tinta;

  static const verde = Accento(foglia, Color(0xFF17694A), Color(0xFFE2F3E9));
  static const arancio = Accento(corallo, Color(0xFFB42318), Color(0xFFFDEBE6));
  static const blu = Accento(cielo, Color(0xFF1A5AAE), Color(0xFFE5EFFC));
  static const giallo = Accento(sole, Color(0xFF8F5B00), Color(0xFFFFF2D2));
  static const viola = Accento(Color(0xFF6E52D4), Color(0xFF6E52D4), Color(0xFFEEEAFB));
  static const acqua = Accento(Color(0xFF14A3A3), Color(0xFF0B6E6E), Color(0xFFDDF4F2));

  /// Grigio, per icone che non devono richiamare una sezione.
  static Accento get neutro => Accento(testoTenue, testoSecondario, sfondo);
}

/// Ricostruisce tutti i widget montati, mantenendone lo stato: serve dopo il
/// cambio di tema, perché i colori sono letti dai getter durante il build.
void ricostruisciTutto(BuildContext context) {
  void segna(Element e) {
    e.markNeedsBuild();
    e.visitChildren(segna);
  }

  (context as Element).visitChildren(segna);
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

TextTheme _testi() {
  final base = (_scuro ? ThemeData.dark() : ThemeData.light()).textTheme.apply(bodyColor: testo, displayColor: testo);
  TextStyle? stretto(TextStyle? t, double spaziatura) => t?.copyWith(letterSpacing: spaziatura, height: 1.2);
  return base.copyWith(
    headlineLarge: stretto(base.headlineLarge, -.6),
    headlineMedium: stretto(base.headlineMedium, -.5),
    headlineSmall: stretto(base.headlineSmall, -.4),
    titleLarge: stretto(base.titleLarge, -.3),
    titleMedium: base.titleMedium?.copyWith(letterSpacing: -.1),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
  );
}

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
    brightness: _scuro ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: foresta,
      brightness: _scuro ? Brightness.dark : Brightness.light,
      primary: foresta,
      onPrimary: Colors.white,
      secondary: foglia,
      surface: superficie,
      onSurface: testo,
      onSurfaceVariant: testoSecondario,
      surfaceContainerHighest: superficieAlta,
      outline: bordoForte,
      outlineVariant: bordo,
      error: coralloScuro,
    ),
    textTheme: _testi(),
    iconTheme: IconThemeData(color: testo),
    scaffoldBackgroundColor: sfondo,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: sfondo,
      surfaceTintColor: Colors.transparent,
      foregroundColor: testo,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: _scuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    navigationBarTheme: NavigationBarThemeData(
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
        side: BorderSide(color: bordoForte, width: 1.4),
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
        side: BorderSide(color: bordo, width: 1.2),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: superficie,
      selectedColor: menta,
      side: BorderSide(color: bordo),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: testo),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    cardTheme: CardThemeData(color: superficie, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(
      backgroundColor: superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: superficie,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: temaScuro ? const Color(0xFF2A3A30) : forestaScura,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: foresta),
    dividerTheme: DividerThemeData(color: bordo, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: TextStyle(fontSize: 14, color: testoSecondario),
      hintStyle: TextStyle(fontSize: 14, color: testoTenue),
      border: campo(bordoForte, 1.2),
      enabledBorder: campo(bordoForte, 1.2),
      focusedBorder: campo(foresta, 2),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Componenti condivisi
// ─────────────────────────────────────────────────────────────────────────────

/// Margine laterale di tutte le schede: titoli, schede ed elenchi partono
/// dalla stessa linea, così passando da una scheda all'altra nulla salta.
const double margineLaterale = 16;

class ContenitorePagina extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  const ContenitorePagina({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // In alto, non al centro: una pagina corta non deve galleggiare a metà schermo.
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Altezza piena: il trascinamento per aggiornare funziona anche sotto il contenuto.
            constraints: BoxConstraints(
              maxWidth: 760,
              minHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
            ),
            child: SingleChildScrollView(
              controller: controller,
              // Scorrimento del sistema: su Android la pagina si ferma al fondo
              // invece di rimbalzare (il rimbalzo «rilanciava» la pagina verso l'alto).
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(margineLaterale, 0, margineLaterale, 32),
              child: child,
            ),
          ),
        ),
      );
}

/// Fa comparire il contenuto con dissolvenza e un breve scivolamento verso l'alto.
/// [indice] ritarda gli elementi successivi per un effetto a cascata: ognuno
/// parte poco dopo il precedente e dura quanto gli altri.
///
/// Usa [FadeTransition] e [SlideTransition]: a ogni fotogramma cambiano solo
/// i parametri di disegno, senza ricostruire il contenuto.
class Appare extends StatefulWidget {
  final Widget child;
  final int indice;
  /// Falso per mostrare subito il contenuto (per esempio un messaggio già
  /// comparso che torna visibile scorrendo l'elenco).
  final bool attiva;
  const Appare({super.key, required this.child, this.indice = 0, this.attiva = true});

  /// Durata della comparsa di un singolo elemento e ritardo tra uno e l'altro.
  static const int durataMs = 360, passoMs = 55;

  @override
  State<Appare> createState() => _AppareState();
}

class _AppareState extends State<Appare> with SingleTickerProviderStateMixin {
  late final int _ritardo = widget.indice.clamp(0, 6) * Appare.passoMs;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: Appare.durataMs + _ritardo),
  );
  late final Animation<double> _curva = _anim.drive(
    CurveTween(curve: Interval(_ritardo / (Appare.durataMs + _ritardo), 1, curve: Curves.easeOutCubic)),
  );
  late final Animation<Offset> _scivola =
      Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(_curva);
  bool _avviata = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_avviata) return;
    _avviata = true;
    if (!widget.attiva || MediaQuery.of(context).disableAnimations) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curva,
        child: SlideTransition(position: _scivola, child: widget.child),
      );
}

/// Curve da dare all'[AnimatedSwitcher] che usa [transizioneMorbida].
const Curve curvaEntrata = Curves.easeOutCubic, curvaUscita = Curves.easeInCubic;

/// Transizione per [AnimatedSwitcher]: dissolvenza con un leggero
/// scivolamento verso l'alto, come [Appare]. Le curve vanno impostate sullo
/// switcher ([curvaEntrata], [curvaUscita]): qui non si crea nessuna
/// CurvedAnimation, perché lo switcher richiama questa funzione a ogni
/// aggiornamento del figlio e ognuna resterebbe in ascolto del controller.
Widget transizioneMorbida(Widget figlio, Animation<double> animazione) => FadeTransition(
      opacity: animazione,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(animazione),
        child: figlio,
      ),
    );

/// Disposizione per [AnimatedSwitcher] allineata in alto: il contenuto
/// uscente non salta al centro quando ha un'altezza diversa dal nuovo.
Widget disposizioneInAlto(Widget? attuale, List<Widget> precedenti) => Stack(
      alignment: Alignment.topCenter,
      children: [...precedenti, ?attuale],
    );

/// [AnimatedSwitcher] con la dissolvenza dell'app e altezza che si adatta
/// con morbidezza al nuovo contenuto.
class CambioMorbido extends StatelessWidget {
  final Widget child;
  final int ms;
  const CambioMorbido({super.key, required this.child, this.ms = 260});

  @override
  Widget build(BuildContext context) {
    final d = durata(context, ms);
    return AnimatedSize(
      duration: d,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: curvaEntrata,
        switchOutCurve: curvaUscita,
        transitionBuilder: transizioneMorbida,
        layoutBuilder: disposizioneInAlto,
        child: child,
      ),
    );
  }
}

/// Si rimpicciolisce un poco mentre lo si preme e torna con un piccolo
/// rimbalzo: dà un riscontro "fisico" a schede e pulsanti.
class Premibile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scala;
  const Premibile({super.key, required this.child, this.onTap, this.scala = .95});

  @override
  State<Premibile> createState() => _PremibileState();
}

class _PremibileState extends State<Premibile> {
  bool _premuto = false;

  void _premi(bool v) {
    if (widget.onTap != null && v != _premuto) setState(() => _premuto = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _premi(true),
        onTapUp: (_) => _premi(false),
        onTapCancel: () => _premi(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _premuto ? widget.scala : 1,
          duration: durata(context, _premuto ? 90 : 260),
          curve: _premuto ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

/// Intestazione di pagina compatta: icona colorata della sezione e titolo
/// sulla stessa riga. [descrizione] è facoltativa e resta su una sola riga,
/// così l'intestazione non ruba spazio al contenuto.
class TitoloPagina extends StatelessWidget {
  final String titolo;
  final String? descrizione;
  final IconData? icona;
  final Accento? accentoScelto;
  Accento get accento => accentoScelto ?? Accento.verde;
  final Widget? azione;

  const TitoloPagina({
    super.key,
    required this.titolo,
    this.descrizione,
    this.icona,
    Accento? accento,
    this.azione,
  }) : accentoScelto = accento;

  /// Altezza fissa dell'intestazione: uguale in ogni scheda, con o senza
  /// descrizione e pulsante, così il contenuto parte sempre alla stessa quota.
  static const double altezza = 64;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: altezza - 18),
          child: Row(
          children: [
            if (icona != null) ...[
              ExcludeSemantics(
                child: IconaTonda(icona!, colore: accento.forte, sfondo: accento.tinta, dimensione: 42),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titolo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: testo,
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    if (descrizione != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        descrizione!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: testoSecondario),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (azione != null) ...[const SizedBox(width: 8), azione!],
          ],
          ),
        ),
      );
}

/// Titolo di sezione con contatore opzionale a destra.
class TitoloSezione extends StatelessWidget {
  final String titolo;
  final String? dettaglio;
  final Accento? accentoScelto;
  Accento get accento => accentoScelto ?? Accento.verde;
  const TitoloSezione(this.titolo, {super.key, this.dettaglio, Accento? accento}) : accentoScelto = accento;

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
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.2),
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
  final Color? coloreScelto;
  Color get colore => coloreScelto ?? foresta;
  final Color? sfondo;
  final double dimensione;
  const IconaTonda(this.icona, {super.key, Color? colore, this.sfondo, this.dimensione = 44}) : coloreScelto = colore;

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
  final Color? coloreScelto;
  Color get colore => coloreScelto ?? superficie;
  final Color? coloreBordo;
  final VoidCallback? onTap;

  const Scheda({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    Color? colore,
    this.coloreBordo,
    this.onTap,
  }) : coloreScelto = colore;

  @override
  Widget build(BuildContext context) {
    final alta = MediaQuery.highContrastOf(context);
    final raggio = BorderRadius.circular(22);
    final contenuto = Padding(padding: padding, child: child);
    final scheda = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: raggio,
        boxShadow: [
          BoxShadow(color: ombra, blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: colore,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: raggio,
          side: BorderSide(
            color: alta ? testo : coloreBordo ?? bordo,
            width: alta ? 1.5 : 1,
          ),
        ),
        child: onTap == null ? contenuto : InkWell(onTap: onTap, child: contenuto),
      ),
    );
    return onTap == null ? scheda : ScalaAlTocco(child: scheda);
  }
}

/// Rimpicciolisce appena il figlio mentre il dito è appoggiato, senza
/// rubare il tocco a InkWell o ai pulsanti che contiene.
class ScalaAlTocco extends StatefulWidget {
  final Widget child;
  final double scala;
  const ScalaAlTocco({super.key, required this.child, this.scala = .975});

  @override
  State<ScalaAlTocco> createState() => _ScalaAlToccoState();
}

class _ScalaAlToccoState extends State<ScalaAlTocco> {
  bool _premuto = false;
  Offset? _inizio;

  void _premi(bool v) {
    if (v != _premuto) setState(() => _premuto = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) {
          _inizio = e.position;
          _premi(true);
        },
        // Se il dito scorre (es. scroll della pagina) la scheda torna normale.
        onPointerMove: (e) {
          if (_inizio != null && (e.position - _inizio!).distance > 12) _premi(false);
        },
        onPointerUp: (_) => _premi(false),
        onPointerCancel: (_) => _premi(false),
        child: AnimatedScale(
          scale: _premuto ? widget.scala : 1,
          duration: durata(context, _premuto ? 100 : 280),
          curve: _premuto ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

/// Piccola etichetta a pillola, con puntino o icona opzionali.
class Etichetta extends StatelessWidget {
  final String testo;
  final Color? coloreScelto;
  Color get colore => coloreScelto ?? foresta;
  final Color? sfondo;
  final IconData? icona;
  final bool puntino;

  const Etichetta(
    this.testo, {
    super.key,
    Color? colore,
    this.sfondo,
    this.icona,
    this.puntino = false,
  }) : coloreScelto = colore;

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
  final Accento? accentoScelto;
  Accento get accento => accentoScelto ?? Accento.verde;

  const Riquadro({super.key, required this.icona, required this.messaggio, Accento? accento}) : accentoScelto = accento;

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
              child: Text(messaggio, style: TextStyle(fontSize: 13.5, height: 1.45, color: testo)),
            ),
          ],
        ),
      );
}

/// «Tira per aggiornare» con i colori dell'app e una vibrazione leggera
/// quando parte l'aggiornamento.
class AggiornaTirando extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const AggiornaTirando({super.key, required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: foresta,
        backgroundColor: superficie,
        strokeWidth: 2.8,
        displacement: 36,
        elevation: temaScuro ? 0 : 2,
        onRefresh: () {
          HapticFeedback.lightImpact();
          return onRefresh();
        },
        child: child,
      );
}

/// Stato vuoto o di errore, con un'azione opzionale per riprovare.
class StatoVuoto extends StatelessWidget {
  final IconData icona;
  final String messaggio;
  final Accento? accentoScelto;
  Accento get accento => accentoScelto ?? Accento.verde;
  final VoidCallback? onAzione;
  final String? etichettaAzione;

  const StatoVuoto({
    super.key,
    required this.icona,
    required this.messaggio,
    Accento? accento,
    this.onAzione,
    this.etichettaAzione,
  }) : accentoScelto = accento;

  @override
  Widget build(BuildContext context) => Appare(
        child: Scheda(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
          child: Column(
            children: [
              ExcludeSemantics(child: IllustrazioneVuota(icona: icona, accento: accento)),
              const SizedBox(height: 14),
              Text(
                messaggio,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, height: 1.45, color: testoSecondario),
              ),
              if (onAzione != null && etichettaAzione != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onAzione,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(etichettaAzione!),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Piccola illustrazione per gli stati vuoti: una macchia morbida nel colore
/// dell'accento, due foglioline e qualche puntino attorno, e l'icona che fluttua.
class IllustrazioneVuota extends StatefulWidget {
  final IconData icona;
  final Accento accento;
  const IllustrazioneVuota({super.key, required this.icona, required this.accento});

  @override
  State<IllustrazioneVuota> createState() => _IllustrazioneVuotaState();
}

class _IllustrazioneVuotaState extends State<IllustrazioneVuota> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = .5;
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
  Widget build(BuildContext context) {
    final a = widget.accento;
    return SizedBox(
      width: 132,
      height: 96,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          return CustomPaint(
            painter: _PittoreVuoto(t, a.base, a.tinta),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, 3 - 6 * t),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: superficie,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: a.base.withValues(alpha: .22), blurRadius: 16, offset: Offset(0, 8 - 4 * t))],
                  ),
                  child: Icon(widget.icona, color: a.forte, size: 28),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PittoreVuoto extends CustomPainter {
  final double t;
  final Color colore;
  final Color tinta;
  _PittoreVuoto(this.t, this.colore, this.tinta);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Macchia morbida e irregolare dietro l'icona.
    final macchia = Path();
    const punti = 7;
    for (var i = 0; i <= punti; i++) {
      final ang = i / punti * 2 * math.pi;
      final r = 40 + 4 * math.sin(ang * 3 + t * 1.4);
      final p = c + Offset(math.cos(ang) * r * 1.18, math.sin(ang) * r * .92);
      if (i == 0) {
        macchia.moveTo(p.dx, p.dy);
      } else {
        final angPrec = (i - .5) / punti * 2 * math.pi;
        final rc = 44 + 4 * math.cos(angPrec * 2 - t);
        final q = c + Offset(math.cos(angPrec) * rc * 1.18, math.sin(angPrec) * rc * .92);
        macchia.quadraticBezierTo(q.dx, q.dy, p.dx, p.dy);
      }
    }
    canvas.drawPath(macchia, Paint()..color = tinta);

    // Due foglioline ai lati, che oscillano appena.
    void foglia(Offset centro, double rot, double scala) {
      canvas.save();
      canvas.translate(centro.dx, centro.dy);
      canvas.rotate(rot);
      canvas.scale(scala);
      final f = Path()
        ..moveTo(0, -9)
        ..quadraticBezierTo(7, 0, 0, 9)
        ..quadraticBezierTo(-7, 0, 0, -9);
      canvas.drawPath(f, Paint()..color = colore.withValues(alpha: .55));
      canvas.drawLine(
        const Offset(0, -6),
        const Offset(0, 7),
        Paint()
          ..color = tinta
          ..strokeWidth = 1.2,
      );
      canvas.restore();
    }

    foglia(c + Offset(-52, -22 + 3 * t), -.7 + .15 * t, 1);
    foglia(c + Offset(54, 18 - 3 * t), 2.3 - .15 * t, .8);

    // Puntini decorativi.
    final punto = Paint()..color = colore.withValues(alpha: .35);
    canvas.drawCircle(c + Offset(44, -32 - 2 * t), 3.2, punto);
    canvas.drawCircle(c + Offset(-40, 32 + 2 * t), 2.4, punto);
    canvas.drawCircle(c + const Offset(-60, 8), 1.8, punto);
  }

  @override
  bool shouldRepaint(_PittoreVuoto old) => old.t != t || old.colore != colore || old.tinta != tinta;
}

/// Fascia di luce che attraversa in diagonale il figlio: l'effetto «shimmer»
/// dei segnaposto di caricamento. Con [animazione] ferma a 0 non si vede.
class Riflesso extends StatelessWidget {
  final Animation<double> animazione;
  final Widget child;
  const Riflesso({super.key, required this.animazione, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animazione,
        child: child,
        builder: (context, figlio) {
          final v = animazione.value;
          if (v == 0) return figlio!;
          final luce = Colors.white.withValues(alpha: temaScuro ? .07 : .75);
          final x = -1.8 + 3.6 * Curves.easeInOut.transform(v);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment(x - .6, -.5),
              end: Alignment(x + .6, .5),
              colors: [luce.withValues(alpha: 0), luce, luce.withValues(alpha: 0)],
            ).createShader(r),
            child: figlio,
          );
        },
      );
}

/// Segnaposto rettangolare con il riflesso, per grafici e immagini in arrivo.
class BloccoInCaricamento extends StatefulWidget {
  final double altezza;
  final String etichetta;
  const BloccoInCaricamento({super.key, required this.altezza, required this.etichetta});

  @override
  State<BloccoInCaricamento> createState() => _BloccoInCaricamentoState();
}

class _BloccoInCaricamentoState extends State<BloccoInCaricamento> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.etichetta,
        child: ExcludeSemantics(
          child: Riflesso(
            animazione: _c,
            child: Container(
              height: widget.altezza,
              width: double.infinity,
              decoration: BoxDecoration(color: bordo.withValues(alpha: .7), borderRadius: BorderRadius.circular(16)),
            ),
          ),
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
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulsazione.value = 0;
    } else if (!_pulsazione.isAnimating) {
      _pulsazione.repeat();
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
          decoration: BoxDecoration(color: bordo, borderRadius: BorderRadius.circular(8)),
        ),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.etichetta,
        child: ExcludeSemantics(
          child: Riflesso(
            animazione: _pulsazione,
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
                              decoration: BoxDecoration(color: bordo, borderRadius: BorderRadius.circular(13)),
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
  final Color? coloreScelto;
  Color get colore => coloreScelto ?? foresta;
  final VoidCallback? onPressed;
  final bool outlined;

  const PulsanteAzione({
    super.key,
    required this.testo,
    required this.icona,
    Color? colore,
    this.onPressed,
    this.outlined = false,
  }) : coloreScelto = colore;

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
              style: FilledButton.styleFrom(backgroundColor: colore, foregroundColor: suAccento),
              onPressed: onPressed,
              child: contenuto,
            ),
    );
  }
}

/// Data detta a parole rispetto a oggi: «oggi», «ieri», «3 giorni fa»,
/// «domani», «tra 2 giorni»; oltre la settimana torna «gg/mm».
String dataRelativa(DateTime d, Copie s, {DateTime? adesso}) {
  final ora = adesso ?? DateTime.now();
  final giorni = DateTime(d.year, d.month, d.day).difference(DateTime(ora.year, ora.month, ora.day)).inDays;
  return switch (giorni) {
    0 => s.t('oggi', 'today'),
    -1 => s.t('ieri', 'yesterday'),
    1 => s.t('domani', 'tomorrow'),
    < 0 && >= -6 => s.t('${-giorni} giorni fa', '${-giorni} days ago'),
    > 1 && <= 6 => s.t('tra $giorni giorni', 'in $giorni days'),
    _ => formattaData(d),
  };
}

/// Formatta una data ISO come "gg/mm" (o "gg/mm hh:mm" con [ora]).
String formattaData(dynamic iso, {bool ora = false}) {
  final d = iso is DateTime ? iso : DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  String due(int n) => n.toString().padLeft(2, '0');
  final giorno = '${due(d.day)}/${due(d.month)}';
  return ora ? '$giorno ${due(d.hour)}:${due(d.minute)}' : giorno;
}

// ─────────────────────────────────────────────────────────────────────────────
// Foto
// ─────────────────────────────────────────────────────────────────────────────

final Map<String, ImageProvider> _immaginiInline = {};

/// Immagine da un URL di foto: `http(s)` dal server oppure `data:` (demo).
/// Le immagini `data:` si decodificano una volta sola e restano in memoria.
ImageProvider? immagineDa(String? url) {
  if (url == null || url.isEmpty) return null;
  if (!url.startsWith('data:')) return NetworkImage(url);
  final giaPronta = _immaginiInline[url];
  if (giaPronta != null) return giaPronta;
  try {
    final img = MemoryImage(UriData.parse(url).contentAsBytes());
    if (_immaginiInline.length > 40) _immaginiInline.clear();
    return _immaginiInline[url] = img;
  } catch (_) {
    return null;
  }
}

/// Foto che si apre a schermo intero al tocco, con un'icona che lo suggerisce.
class FotoApribile extends StatelessWidget {
  final String url;
  final double altezza;
  final String etichetta;

  const FotoApribile({super.key, required this.url, this.altezza = 190, this.etichetta = 'Foto'});

  @override
  Widget build(BuildContext context) {
    final img = immagineDa(url);
    if (img == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      image: true,
      label: etichetta,
      child: GestureDetector(
        onTap: () => apriFotoSchermoIntero(context, url),
        child: Stack(
          children: [
            Image(
              image: img,
              height: altezza,
              width: double.infinity,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, sincrono) => sincrono
                  ? child
                  : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: durata(context, 300), child: child),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), shape: BoxShape.circle),
                child: const Icon(Icons.open_in_full_rounded, size: 17, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mostra la foto a tutto schermo: pizzico o doppio tocco per ingrandire.
Future<void> apriFotoSchermoIntero(BuildContext context, String url) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: durata(context, 220),
      reverseTransitionDuration: durata(context, 180),
      pageBuilder: (_, _, _) => _FotoSchermoIntero(url: url),
      transitionsBuilder: (_, animazione, _, figlio) => FadeTransition(opacity: animazione, child: figlio),
    ),
  );
}

class _FotoSchermoIntero extends StatefulWidget {
  final String url;
  const _FotoSchermoIntero({required this.url});

  @override
  State<_FotoSchermoIntero> createState() => _FotoSchermoInteroState();
}

class _FotoSchermoInteroState extends State<_FotoSchermoIntero> {
  final TransformationController _trasformazione = TransformationController();
  Offset _ultimoTocco = Offset.zero;

  @override
  void dispose() {
    _trasformazione.dispose();
    super.dispose();
  }

  void _doppioTocco() {
    if (_trasformazione.value.getMaxScaleOnAxis() > 1.01) {
      _trasformazione.value = Matrix4.identity();
    } else {
      const scala = 2.5;
      final p = _ultimoTocco;
      _trasformazione.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (scala - 1), -p.dy * (scala - 1), 0, 1)
        ..scaleByDouble(scala, scala, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = immagineDa(widget.url);
    return Scaffold(
      backgroundColor: Colors.black,
      // Lo Stack deve riempire lo schermo: altrimenti prende la misura del
      // pulsante di chiusura e la foto finisce in un riquadro minuscolo.
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _ultimoTocco = d.localPosition,
              onDoubleTap: _doppioTocco,
              child: InteractiveViewer(
                transformationController: _trasformazione,
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: img == null
                      ? const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)
                      : Image(
                          image: img,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, figlio, progresso) => progresso == null
                              ? figlio
                              : const CircularProgressIndicator(color: Colors.white),
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                        ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: .55)),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}
