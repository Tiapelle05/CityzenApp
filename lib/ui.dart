import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// Un verde foresta come colore dell'app, più quattro accenti caldi e freddi
// che danno a ogni sezione la sua identità. Le varianti "Scuro" servono per
// i testi (sul tema scuro sono più chiare, per leggersi sul fondo), le
// "Chiaro" per gli sfondi tenui.
//
// I colori dipendono dal tema attivo: si leggono dalla [Tavolozza] corrente,
// che l'app cambia con [usaTavolozza] prima di ricostruire tutto.
// ─────────────────────────────────────────────────────────────────────────────

class Tavolozza {
  final bool scura;
  final Color foresta, forestaScura, foglia, menta;
  final Color sole, soleScuro, soleChiaro;
  final Color cielo, cieloScuro, cieloChiaro;
  final Color corallo, coralloScuro, coralloChiaro;
  final Color lavanda, lavandaChiaro;
  final Color acqua, acquaForte, acquaChiaro;
  final Color sfondo, superficie, testo, testoSecondario, testoTenue, bordo, bordoForte;
  /// Riempimento dei segnaposto di caricamento.
  final Color scheletro;

  const Tavolozza({
    required this.scura,
    required this.foresta,
    required this.forestaScura,
    required this.foglia,
    required this.menta,
    required this.sole,
    required this.soleScuro,
    required this.soleChiaro,
    required this.cielo,
    required this.cieloScuro,
    required this.cieloChiaro,
    required this.corallo,
    required this.coralloScuro,
    required this.coralloChiaro,
    required this.lavanda,
    required this.lavandaChiaro,
    required this.acqua,
    required this.acquaForte,
    required this.acquaChiaro,
    required this.sfondo,
    required this.superficie,
    required this.testo,
    required this.testoSecondario,
    required this.testoTenue,
    required this.bordo,
    required this.bordoForte,
    required this.scheletro,
  });

  static const chiara = Tavolozza(
    scura: false,
    foresta: Color(0xFF17694A),
    forestaScura: Color(0xFF0E4532),
    foglia: Color(0xFF2FA36B),
    menta: Color(0xFFE2F3E9),
    sole: Color(0xFFF0A202),
    soleScuro: Color(0xFF8F5B00),
    soleChiaro: Color(0xFFFFF2D2),
    cielo: Color(0xFF2C7BE5),
    cieloScuro: Color(0xFF1A5AAE),
    cieloChiaro: Color(0xFFE5EFFC),
    corallo: Color(0xFFE4572E),
    coralloScuro: Color(0xFFB42318),
    coralloChiaro: Color(0xFFFDEBE6),
    lavanda: Color(0xFF6E52D4),
    lavandaChiaro: Color(0xFFEEEAFB),
    acqua: Color(0xFF14A3A3),
    acquaForte: Color(0xFF0B6E6E),
    acquaChiaro: Color(0xFFDDF4F2),
    sfondo: Color(0xFFF4F6F1),
    superficie: Color(0xFFFFFFFF),
    testo: Color(0xFF14231A),
    testoSecondario: Color(0xFF5B6B60),
    testoTenue: Color(0xFF8A988E),
    bordo: Color(0xFFE1E8DD),
    bordoForte: Color(0xFFC9D6C6),
    scheletro: Color(0xFFE6ECE3),
  );

  /// Fondo verde-nero, superfici appena più chiare; gli accenti restano
  /// riconoscibili e le loro varianti per i testi diventano chiare.
  static const scuraNotte = Tavolozza(
    scura: true,
    foresta: Color(0xFF2E9A69),
    forestaScura: Color(0xFFA8E2C4),
    foglia: Color(0xFF3FBF83),
    menta: Color(0xFF183A2B),
    sole: Color(0xFFF0A202),
    soleScuro: Color(0xFFFFC857),
    soleChiaro: Color(0xFF3A2E0E),
    cielo: Color(0xFF4D94F2),
    cieloScuro: Color(0xFF8EBEFF),
    cieloChiaro: Color(0xFF132A4A),
    corallo: Color(0xFFF06B45),
    coralloScuro: Color(0xFFFF8F75),
    coralloChiaro: Color(0xFF3E1E17),
    lavanda: Color(0xFF9C88F2),
    lavandaChiaro: Color(0xFF2A2452),
    acqua: Color(0xFF1FB5B5),
    acquaForte: Color(0xFF6FDCDC),
    acquaChiaro: Color(0xFF0F3433),
    sfondo: Color(0xFF0E1511),
    superficie: Color(0xFF172019),
    testo: Color(0xFFE6EEE8),
    testoSecondario: Color(0xFFA4B3A8),
    testoTenue: Color(0xFF76867B),
    bordo: Color(0xFF29352C),
    bordoForte: Color(0xFF3A483E),
    scheletro: Color(0xFF243027),
  );
}

Tavolozza _tavolozza = Tavolozza.chiara;

/// Tavolozza in uso. Cambiarla non ridisegna nulla da sola: l'app la cambia
/// e subito dopo ricostruisce tutte le schermate.
Tavolozza get tavolozza => _tavolozza;
void usaTavolozza(Tavolozza t) => _tavolozza = t;

/// Vero col tema scuro: per i pochi punti che non bastano i colori della tavolozza.
bool get temaScuro => _tavolozza.scura;

/// Testo e icone sopra un riempimento d'accento (pulsanti pieni, segnaposto,
/// filtri scelti): bianco sul tema chiaro, scuro sul tema scuro, dove gli
/// accenti diventano chiari per leggersi sul fondo.
Color get suAccento => _tavolozza.scura ? const Color(0xFF0E1511) : Colors.white;

Color get foresta => _tavolozza.foresta;
Color get forestaScura => _tavolozza.forestaScura;
Color get foglia => _tavolozza.foglia;
Color get menta => _tavolozza.menta;

Color get sole => _tavolozza.sole;
Color get soleScuro => _tavolozza.soleScuro;
Color get soleChiaro => _tavolozza.soleChiaro;

Color get cielo => _tavolozza.cielo;
Color get cieloScuro => _tavolozza.cieloScuro;
Color get cieloChiaro => _tavolozza.cieloChiaro;

Color get corallo => _tavolozza.corallo;
Color get coralloScuro => _tavolozza.coralloScuro;
Color get coralloChiaro => _tavolozza.coralloChiaro;

Color get lavanda => _tavolozza.lavanda;
Color get lavandaChiaro => _tavolozza.lavandaChiaro;

Color get sfondo => _tavolozza.sfondo;
Color get superficie => _tavolozza.superficie;
Color get testo => _tavolozza.testo;
Color get testoSecondario => _tavolozza.testoSecondario;
Color get testoTenue => _tavolozza.testoTenue;
Color get bordo => _tavolozza.bordo;
Color get bordoForte => _tavolozza.bordoForte;

/// Terna di colori di un accento: [base] per decorazioni, [forte] per testi e
/// icone, [tinta] per gli sfondi tenui.
class Accento {
  final Color base;
  final Color forte;
  final Color tinta;
  const Accento(this.base, this.forte, this.tinta);

  static Accento get verde => Accento(foglia, foresta, menta);
  static Accento get arancio => Accento(corallo, coralloScuro, coralloChiaro);
  static Accento get blu => Accento(cielo, cieloScuro, cieloChiaro);
  static Accento get giallo => Accento(sole, soleScuro, soleChiaro);
  static Accento get viola => Accento(lavanda, lavanda, lavandaChiaro);
  static Accento get acqua => Accento(_tavolozza.acqua, _tavolozza.acquaForte, _tavolozza.acquaChiaro);
  /// Grigio, per icone che non devono richiamare una sezione.
  static Accento get neutro => Accento(testoTenue, testoSecondario, sfondo);

  @override
  bool operator ==(Object other) =>
      other is Accento && other.base == base && other.forte == forte && other.tinta == tinta;

  @override
  int get hashCode => Object.hash(base, forte, tinta);
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
    brightness: temaScuro ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: foresta,
      brightness: temaScuro ? Brightness.dark : Brightness.light,
      primary: foresta,
      onPrimary: suAccento,
      secondary: foglia,
      surface: superficie,
      onSurface: testo,
      error: coralloScuro,
    ),
    textTheme: (temaScuro ? ThemeData.dark() : ThemeData.light()).textTheme.apply(bodyColor: testo, displayColor: testo),
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
        selectedForegroundColor: suAccento,
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

/// Rimpicciolisce leggermente il contenuto mentre lo si preme, per un
/// riscontro immediato al tocco (oltre all'increspatura del Material).
/// Non intercetta i gesti: il tocco arriva comunque al figlio.
class Premibile extends StatefulWidget {
  final Widget child;
  final bool attivo;
  final double scala;
  const Premibile({super.key, required this.child, this.attivo = true, this.scala = .97});

  @override
  State<Premibile> createState() => _PremibileState();
}

class _PremibileState extends State<Premibile> {
  bool _premuto = false;
  Offset _inizio = Offset.zero;

  void _imposta(bool v) {
    if (_premuto != v && mounted) setState(() => _premuto = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.attivo) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _inizio = e.position;
        _imposta(true);
      },
      // Se il dito scorre la pagina non è più un tocco: la scheda torna subito com'era.
      onPointerMove: (e) {
        if (_premuto && (e.position - _inizio).distance > kTouchSlop) _imposta(false);
      },
      onPointerUp: (_) => _imposta(false),
      onPointerCancel: (_) => _imposta(false),
      child: AnimatedScale(
        scale: _premuto ? widget.scala : 1,
        duration: durata(context, _premuto ? 90 : 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
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
            color: alta ? testo : coloreBordo ?? bordo,
            width: alta ? 1.5 : 1,
          ),
        ),
        child: onTap == null ? contenuto : InkWell(onTap: onTap, child: contenuto),
      ),
    );
    return onTap == null ? scheda : Premibile(scala: .985, child: scheda);
  }
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
  Widget build(BuildContext context) => Scheda(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            ExcludeSemantics(child: IconaTonda(icona, colore: accento.forte, sfondo: accento.tinta, dimensione: 58)),
            const SizedBox(height: 14),
            Text(
              messaggio,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.45, color: testoSecondario),
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
  late final Animation<double> _opacita =
      Tween<double>(begin: .45, end: 1).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulsazione);

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
          decoration: BoxDecoration(color: tavolozza.scheletro, borderRadius: BorderRadius.circular(8)),
        ),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.etichetta,
        child: ExcludeSemantics(
          child: FadeTransition(
            opacity: _opacita,
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
                              decoration: BoxDecoration(color: tavolozza.scheletro, borderRadius: BorderRadius.circular(13)),
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
