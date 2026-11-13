import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'citizen_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await CitizenApi.instance.initialize().timeout(const Duration(seconds: 5));
  } catch (_) {
    // L'app resta utilizzabile anche se il backend non è ancora avviato.
  }
  runApp(const ParkApp());
}

const Color verdeScuro = Color(0xFF244B35);       // Verde bosco profondo: azioni principali
const Color verdeProfondo = Color(0xFF17271D);    // Verde quasi nero: testo e contrasti
const Color verdePrincipale = Color(0xFF718B65);  // Verde foglia
const Color verdeMedio = Color(0xFF718B65);       // Verde foglia: indicatori
const Color verdeAccento = Color(0xFF244B35);     // Verde bosco di accento
const Color verdeIntermedio = Color(0xFFA3A65A);  // Verde oliva
const Color verde = Color(0xFF244B35);
const Color sfondo = Color(0xFFDCE8D8);            // Sfondo salvia chiaro
const Color testo = Color(0xFF17271D);
const Color testoSecondario = Color(0xFF455448);
const Color bordo = Color(0xFF9BAA8D);  // Bordo verde-grigio visibile
const Color verdeChiaro = Color(0xFFDCE6D3);
const Color verdePallido = Color(0xFFEAF0E3);
const Color superficieVerde = Color(0xFFFFFDF7);

class Copie {
  final bool inglese;
  const Copie(this.inglese);

  String t(String italiano, String english) => inglese ? english : italiano;
}

enum StatoParco {
  ottimo('Ottimo', 'Excellent', 1, verde),
  buono('Buono', 'Good', .75, verde),
  discreto('Da monitorare', 'Needs attention', .5, Color(0xFF8A5A00)),
  cattivo('Attenzione richiesta', 'Attention required', .25, Color(0xFFB42318)),
  nonDisponibile('Non disponibile', 'Unavailable', 0, testoSecondario);

  const StatoParco(this.italiano, this.english, this.progresso, this.colore);

  final String italiano;
  final String english;
  final double progresso;
  final Color colore;
}

StatoParco _statoDaBackend(Map<String, dynamic>? data) {
  switch (data?['level']) {
    case 'ok': return StatoParco.buono;
    case 'warning': return StatoParco.discreto;
    case 'alert': return StatoParco.cattivo;
    default: return StatoParco.nonDisponibile;
  }
}

String _descrizioneStatoDaBackend(Map<String, dynamic>? data, Copie s) {
  switch (data?['level']) {
    case 'ok':
      return s.t(
        'Nessuna criticità aperta segnalata.',
        'No open issues are currently reported.',
      );
    case 'warning':
      final openIssues = data?['open_issues'];
      if (openIssues is int && openIssues > 0) {
        return openIssues == 1
            ? s.t(
                '1 situazione aperta è in gestione.',
                '1 open issue is being addressed.',
              )
            : s.t(
                '$openIssues situazioni aperte sono in gestione.',
                '$openIssues open issues are being addressed.',
              );
      }
      return s.t(
        'È attivo un avviso del parco.',
        'A park notice is active.',
      );
    case 'alert':
      return s.t(
        'È attivo un avviso importante del parco.',
        'An important park notice is active.',
      );
    default:
      return s.t(
        'Lo stato del parco non è al momento disponibile.',
        'Park status is currently unavailable.',
      );
  }
}

class ParkApp extends StatefulWidget {
  const ParkApp({super.key});

  @override
  State<ParkApp> createState() => _ParkAppState();
}

class TreeyesApp extends ParkApp {
  const TreeyesApp({super.key}) : super();
}

class _ParkAppState extends State<ParkApp> {
  bool _inglese = false;

  @override
  Widget build(BuildContext context) {
    const colorePrimario = verdeScuro;
    const coloreTesto = testo;
    const coloreSecondario = testoSecondario;
    const coloreBordo = bordo;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tryees',
      theme: ThemeData(
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        colorScheme: ColorScheme.fromSeed(
          seedColor: colorePrimario,
          primary: colorePrimario,
          secondary: verdePrincipale,
          surface: superficieVerde,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: coloreTesto,
          displayColor: coloreTesto,
        ),
        scaffoldBackgroundColor: sfondo,
        appBarTheme: AppBarTheme(
          backgroundColor: sfondo,
          foregroundColor: coloreTesto,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFDF7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          labelStyle: TextStyle(fontSize: 14, color: coloreSecondario),
          hintStyle: TextStyle(fontSize: 14, color: coloreSecondario),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: coloreBordo, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: coloreBordo, width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorePrimario, width: 2),
          ),
        ),
      ),
      home: NavigazionePrincipale(
        inglese: _inglese,
        onLinguaCambiata: (valore) => setState(() => _inglese = valore),
      ),
    );
  }
}

class NavigazionePrincipale extends StatefulWidget {
  final bool inglese;
  final ValueChanged<bool> onLinguaCambiata;

  const NavigazionePrincipale({
    super.key,
    required this.inglese,
    required this.onLinguaCambiata,
  });

  @override
  State<NavigazionePrincipale> createState() => _NavigazionePrincipaleState();
}

class _NavigazionePrincipaleState extends State<NavigazionePrincipale> {
  int _pagina = 0;

  void _vaiA(int indice) {
    setState(() => _pagina = indice);
    if (indice == 0) unawaited(_aggiornaStatoParco());
  }

  Future<void> _aggiornaStatoParco() async {
    try {
      await CitizenApi.instance.getParkStatus();
    } catch (_) {
      // La schermata mostra lo stato memorizzato se il backend non è raggiungibile.
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Copie(widget.inglese);
    final pagine = [
      SchermataInizio(s: s, onSegnalazioni: () => _vaiA(1)),
      SchermataSegnalazione(s: s),
      SchermataIdee(s: s),
      SchermataAvvisi(s: s),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [verde, verdePrincipale],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.park_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'Tryees',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: verde,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<bool>(
            tooltip: s.t('Cambia lingua', 'Change language'),
            icon: const Icon(Icons.language_rounded, size: 25),
            onSelected: widget.onLinguaCambiata,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<bool>(
                value: false,
                checked: !widget.inglese,
                child: const Row(
                  children: [
                    Text('🇮🇹'),
                    SizedBox(width: 10),
                    Text('Italiano'),
                  ],
                ),
              ),
              CheckedPopupMenuItem<bool>(
                value: true,
                checked: widget.inglese,
                child: const Row(
                  children: [
                    Text('🇬🇧'),
                    SizedBox(width: 10),
                    Text('English'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _pagina, children: pagine),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pagina,
        onDestinationSelected: _vaiA,
        height: 80,
        backgroundColor: const Color(0xFFC8DCC5),
        indicatorColor: const Color(0xFFDCE6D3),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded, color: verde),
            label: s.t('Inizio', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_a_photo_outlined),
            selectedIcon: const Icon(Icons.add_a_photo_rounded, color: verdeMedio),
            label: s.t('Segnala', 'Report'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.lightbulb_outline_rounded),
            selectedIcon: const Icon(
              Icons.lightbulb_rounded,
              color: verdeIntermedio,
            ),
            label: s.t('Idee', 'Ideas'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none_rounded),
            selectedIcon: const Icon(Icons.notifications_rounded, color: verdeScuro),
            label: s.t('Avvisi', 'Notices'),
          ),
        ],
      ),
    );
  }
}

class ContenitorePagina extends StatelessWidget {
  final Widget child;
  const ContenitorePagina({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 380 ? 14 : 20,
            12,
            constraints.maxWidth < 380 ? 14 : 20,
            28,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class TitoloPagina extends StatelessWidget {
  final String titolo;
  final String descrizione;
  final Color colore;
  const TitoloPagina({
    super.key,
    required this.titolo,
    required this.descrizione,
    this.colore = verdeScuro,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 19),
    child: Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titolo,
            style: const TextStyle(
              color: testo,
              fontSize: 27,
              height: 1.18,
              fontWeight: FontWeight.w900,
              letterSpacing: -.35,
            ),
          ),
          const SizedBox(height: 9),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: colore,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            descrizione,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: testoSecondario,
            ),
          ),
        ],
      ),
    ),
  );
}

class Scheda extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color colore;
  final Color? coloreBordo;

  const Scheda({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.colore = const Color(0xFFC8DCC5),
    this.coloreBordo,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: colore,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: MediaQuery.highContrastOf(context)
            ? Colors.black
            : coloreBordo ?? bordo,
        width: MediaQuery.highContrastOf(context) ? 1.5 : 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0817271D),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
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
    required this.colore,
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
        Flexible(
          child: Text(
            testo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colore,
                side: BorderSide(color: colore, width: 1.5),
                minimumSize: const Size(0, 54),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              child: contenuto,
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colore,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 54),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              child: contenuto,
            ),
    );
  }
}

class _MappaIllustrativa extends StatelessWidget {
  final Copie s;

  const _MappaIllustrativa({required this.s});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      height: 190,
      width: double.infinity,
      child: CustomPaint(
        painter: _PittoreMappa(
          coloreArea: const Color(0xFFEAF0E3),
          coloreAlberi: const Color(0xFF315C45),
          coloreSentiero: const Color(0xFF718B65),
          coloreAcqua: const Color(0xFF718B65),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 16,
              child: _EtichettaMappa(
                icona: Icons.park_rounded,
                etichetta: s.t('Ingresso', 'Entrance'),
              ),
            ),
            Positioned(
              right: 16,
              top: 72,
              child: _EtichettaMappa(
                icona: Icons.water_drop_rounded,
                etichetta: s.t('Laghetto', 'Pond'),
                colore: const Color(0xFF315C45),
              ),
            ),
            Positioned(
              left: 40,
              bottom: 17,
              child: _EtichettaMappa(
                icona: Icons.sports_esports_rounded,
                etichetta: s.t('Area giochi', 'Playground'),
                colore: verdeMedio,
              ),
            ),
            Positioned(
              right: 16,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  size: 18,
                  color: verde,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EtichettaMappa extends StatelessWidget {
  final IconData icona;
  final String etichetta;
  final Color colore;

  const _EtichettaMappa({
    required this.icona,
    required this.etichetta,
    this.colore = verde,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF0FFFDF7),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A17271D),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icona, color: colore, size: 16),
          const SizedBox(width: 5),
          Text(
            etichetta,
            style: const TextStyle(
              color: testo,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PittoreMappa extends CustomPainter {
  final Color coloreArea;
  final Color coloreAlberi;
  final Color coloreSentiero;
  final Color coloreAcqua;

  const _PittoreMappa({
    required this.coloreArea,
    required this.coloreAlberi,
    required this.coloreSentiero,
    required this.coloreAcqua,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scalaX = size.width / 360;
    final scalaY = size.height / 190;
    canvas.scale(scalaX, scalaY);
    const larghezza = 360.0;
    const altezza = 190.0;

    canvas.drawRect(
      Offset.zero & Size(larghezza, altezza),
      Paint()..color = coloreArea,
    );

    final prato = Paint()..color = const Color(0xFF8FAF91);
    canvas.drawOval(Rect.fromLTWH(25, 30, 108, 65), prato);
    canvas.drawOval(Rect.fromLTWH(186, 117, 130, 54), prato);

    final stagno = Path()
      ..moveTo(larghezza - 92, 0)
      ..quadraticBezierTo(larghezza - 48, 23, larghezza, 14)
      ..lineTo(larghezza, 57)
      ..quadraticBezierTo(larghezza - 45, 50, larghezza - 86, 28)
      ..close();
    canvas.drawPath(stagno, Paint()..color = coloreAcqua);

    final sentiero = Path()
      ..moveTo(-8, altezza * .76)
      ..cubicTo(72, altezza * .68, 84, altezza * .42, 151, altezza * .48)
      ..cubicTo(225, altezza * .55, 207, altezza * .81, 282, altezza * .67)
      ..cubicTo(
        319,
        altezza * .60,
        larghezza - 16,
        altezza * .48,
        larghezza + 12,
        altezza * .51,
      );
    canvas.drawPath(
      sentiero,
      Paint()
        ..color = coloreSentiero
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      sentiero,
      Paint()
        ..color = const Color(0xFF8FAF91)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    const alberi = <Offset>[
      Offset(31, 119),
      Offset(62, 144),
      Offset(93, 112),
      Offset(126, 128),
      Offset(164, 34),
      Offset(193, 65),
      Offset(229, 32),
      Offset(272, 95),
      Offset(305, 110),
      Offset(145, 161),
      Offset(222, 157),
      Offset(321, 42),
    ];
    for (final albero in alberi) {
      final posizione = albero;
      canvas.drawCircle(posizione, 7, Paint()..color = coloreAlberi);
      canvas.drawCircle(
        posizione.translate(-2, -2),
        2.2,
        Paint()..color = const Color(0xFF718B65),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PittoreMappa oldDelegate) =>
      coloreArea != oldDelegate.coloreArea ||
      coloreAlberi != oldDelegate.coloreAlberi ||
      coloreSentiero != oldDelegate.coloreSentiero ||
      coloreAcqua != oldDelegate.coloreAcqua;
}

class SchermataInizio extends StatefulWidget {
  final Copie s;
  final VoidCallback onSegnalazioni;

  const SchermataInizio({super.key, required this.s, required this.onSegnalazioni});

  @override
  State<SchermataInizio> createState() => _SchermataInizioState();
}

class _SchermataInizioState extends State<SchermataInizio> {
  @override
  void initState() {
    super.initState();
    unawaited(_aggiornaStato());
  }

  Future<void> _aggiornaStato() async {
    try {
      await CitizenApi.instance.getParkStatus();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final statoBackend = CitizenApi.instance.cachedParkStatus;
    final stato = _statoDaBackend(statoBackend);
    final descrizioneStato = _descrizioneStatoDaBackend(statoBackend, s);
    final testoCard = MediaQuery.highContrastOf(context) ? Colors.black : testo;
    final testoSecondarioCard = MediaQuery.highContrastOf(context)
        ? Colors.black
        : testoSecondario;

    return ContenitorePagina(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitoloPagina(
            titolo: s.t('Esplora il parco', 'Explore the park'),
            descrizione: s.t(
              'Orientati, scopri lo stato del parco e resta aggiornato.',
              'Find your way, check the park status and stay up to date.',
            ),
            colore: verde,
          ),
          Scheda(
            colore: const Color(0xFFC8DCC5),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.map_outlined, color: verde, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.t('Mappa del parco', 'Park map'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: testoCard,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  image: true,
                  label: s.t(
                    'Mappa illustrativa del parco con sentieri, ingresso, laghetto e area giochi.',
                    'Illustrated park map with paths, entrance, pond and playground.',
                  ),
                  child: _MappaIllustrativa(s: s),
                ),
                const SizedBox(height: 7),
                Text(
                  s.t('Mappa illustrativa', 'Illustrative map'),
                  style: TextStyle(fontSize: 13, color: testoSecondarioCard),
                ),
                const SizedBox(height: 14),
                Semantics(
                  container: true,
                  label: s.t('Stato del parco', 'Park status'),
                  value: s.t(stato.italiano, stato.english),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB2CBAE),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0xFF8FAF91)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.eco_outlined, color: stato.colore, size: 23),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                s.t('Stato del parco', 'Park status'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: testoCard,
                                ),
                              ),
                            ),
                            Text(
                              s.t(stato.italiano, stato.english),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: stato.colore),
                            ),
                            IconButton(tooltip: s.t('Aggiorna stato', 'Refresh status'), onPressed: _aggiornaStato, icon: const Icon(Icons.refresh_rounded, size: 19, color: verde)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Semantics(
                          label: s.t(
                            'Indicatore illustrativo dello stato del parco',
                            'Illustrative park status indicator',
                          ),
                          value: s.t(stato.italiano, stato.english),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: stato.progresso),
                            duration: MediaQuery.of(context).disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, progresso, child) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progresso,
                                minHeight: 9,
                                color: stato.colore,
                                backgroundColor: MediaQuery.highContrastOf(context)
                                    ? testoSecondario
                                    : const Color(0xFF8FAF91),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          descrizioneStato,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: testoSecondarioCard,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PulsanteAzione(
            testo: s.t('Segnala un problema', 'Report a problem'),
            icona: Icons.add_location_alt_outlined,
            colore: verdeScuro,
            onPressed: widget.onSegnalazioni,
          ),
        ],
      ),
    );
  }
}

class SchermataSegnalazione extends StatefulWidget {
  final Copie s;
  const SchermataSegnalazione({super.key, required this.s});

  @override
  State<SchermataSegnalazione> createState() => _SchermataSegnalazioneState();
}

class _SchermataSegnalazioneState extends State<SchermataSegnalazione> {
  final TextEditingController _descrizione = TextEditingController();

  int _passaggio = 0;
  String? _categoria;
  String _gravita = 'media';
  String? _errore;

  static const List<_CategoriaSegnalazione> _categorie = [
    _CategoriaSegnalazione(
      id: 'rifiuti',
      nomeIt: 'Rifiuti e sporcizia',
      nomeEn: 'Waste and litter',
      icona: Icons.delete_outline_rounded,
      colore: verdeMedio,
      sfondo: verdePallido,
    ),
    _CategoriaSegnalazione(
      id: 'verde',
      nomeIt: 'Alberi e vegetazione',
      nomeEn: 'Trees and vegetation',
      icona: Icons.park_outlined,
      colore: verde,
      sfondo: verdeChiaro,
    ),
    _CategoriaSegnalazione(
      id: 'strutture',
      nomeIt: 'Panchine, giochi e strutture',
      nomeEn: 'Benches, playgrounds and facilities',
      icona: Icons.foundation_outlined,
      colore: verdeIntermedio,
      sfondo: verdePallido,
    ),
    _CategoriaSegnalazione(
      id: 'illuminazione',
      nomeIt: 'Illuminazione',
      nomeEn: 'Lighting',
      icona: Icons.lightbulb_outline_rounded,
      colore: verdeAccento,
      sfondo: verdePallido,
    ),
    _CategoriaSegnalazione(
      id: 'sentieri',
      nomeIt: 'Sentieri e pavimentazione',
      nomeEn: 'Paths and paving',
      icona: Icons.route_rounded,
      colore: verdePrincipale,
      sfondo: verdePallido,
    ),
    _CategoriaSegnalazione(
      id: 'altro',
      nomeIt: 'Altro',
      nomeEn: 'Other',
      icona: Icons.more_horiz_rounded,
      colore: verdeIntermedio,
      sfondo: verdePallido,
    ),
  ];

  @override
  void dispose() {
    _descrizione.dispose();
    super.dispose();
  }

  void _mostraErrore(String messaggio) {
    setState(() => _errore = messaggio);
  }

  void _vaiAvanti() {
    final s = widget.s;
    if (_passaggio == 0 && _categoria == null) {
      _mostraErrore(
        s.t(
          'Seleziona una categoria per continuare.',
          'Choose a category to continue.',
        ),
      );
      return;
    }

    if (_passaggio < 2) {
      setState(() {
        _errore = null;
        _passaggio++;
      });
    } else {
      _mostraConferma();
    }
  }

  void _tornaIndietro() {
    if (_passaggio > 0) {
      setState(() {
        _errore = null;
        _passaggio--;
      });
    }
  }

  XFile? _foto;
  Position? _posizione;
  bool _caricamentoGps = false;
  bool _invioInCorso = false;

  Future<void> _selezionaFoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 82, maxWidth: 1600);
      if (!mounted || file == null) return;
      setState(() { _foto = file; _errore = null; });
    } catch (e) {
      _mostraErrore('Impossibile aprire la fotocamera o la galleria: $e');
    }
  }

  Future<void> _rilevaPosizione() async {
    setState(() { _caricamentoGps = true; _errore = null; });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Attiva la posizione GPS sul dispositivo.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Permesso di localizzazione non concesso.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() => _posizione = position);
    } catch (e) {
      if (mounted) _mostraErrore(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _caricamentoGps = false);
    }
  }

  Future<void> _mostraConferma() async {
    final s = widget.s;
    if (_posizione == null) {
      _mostraErrore(s.t('Rileva la posizione GPS prima di inviare la segnalazione.', 'Get the GPS location before submitting the report.'));
      setState(() => _passaggio = 1);
      return;
    }
    setState(() { _invioInCorso = true; _errore = null; });
    try {
      const categorieBackend = {
        'rifiuti': 'waste', 'verde': 'green', 'strutture': 'furniture',
        'illuminazione': 'lighting', 'sentieri': 'other', 'altro': 'other',
      };
      final categoria = categorieBackend[_categoria] ?? 'other';
      final nomeCategoria = _categorie.firstWhere((c) => c.id == _categoria).nomeIt;
      final descrizione = _descrizione.text.trim().length >= 10
          ? _descrizione.text.trim()
          : 'Problema segnalato: $nomeCategoria';
      final result = await CitizenApi.instance.createProblemReport(
        category: categoria,
        description: descrizione,
        priority: _gravita == 'bassa' ? 'low' : _gravita == 'alta' ? 'high' : 'medium',
        latitude: _posizione!.latitude,
        longitude: _posizione!.longitude,
        photoBytes: _foto == null ? null : await _foto!.readAsBytes(),
        photoName: _foto?.name,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const CircleAvatar(radius: 32, backgroundColor: verdeChiaro, child: Icon(Icons.check_rounded, color: verde, size: 38)),
          title: Text(s.t('Segnalazione inviata', 'Report submitted')),
          content: Text('${s.t('Codice', 'Code')}: ${result['code'] ?? result['id']}\n${result['status_label'] ?? ''}'),
          actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s.t('Ho capito', 'Done')))],
        ),
      );
      if (!mounted) return;
      setState(() {
        _passaggio = 0; _categoria = null; _gravita = 'media';
        _descrizione.clear(); _errore = null; _foto = null; _posizione = null;
      });
    } catch (e) {
      if (mounted) _mostraErrore(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _invioInCorso = false);
    }
  }

  Widget _indicatorePassaggi(Copie s) {
    final nomi = [
      s.t('Problema', 'Issue'),
      s.t('Foto e luogo', 'Photo and place'),
      s.t('Riepilogo', 'Review'),
    ];

    return Semantics(
      container: true,
      liveRegion: true,
      label: s.t(
        'Passaggio ${_passaggio + 1} di 3: ${nomi[_passaggio]}',
        'Step ${_passaggio + 1} of 3: ${nomi[_passaggio]}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              3,
              (indice) => Expanded(
                child: Container(
                  height: 7,
                  margin: EdgeInsets.only(right: indice == 2 ? 0 : 7),
                  decoration: BoxDecoration(
                    color: indice <= _passaggio ? verde : bordo,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            s.t(
              'PASSAGGIO ${_passaggio + 1} DI 3 · ${nomi[_passaggio].toUpperCase()}',
              'STEP ${_passaggio + 1} OF 3 · ${nomi[_passaggio].toUpperCase()}',
            ),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: verde,
              letterSpacing: .35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _schedaCategoria(_CategoriaSegnalazione categoria, Copie s) {
    final selezionata = _categoria == categoria.id;
    final nome = s.t(categoria.nomeIt, categoria.nomeEn);

    void selezionaCategoria() {
      setState(() {
        _categoria = categoria.id;
        _errore = null;
      });
    }

    return Semantics(
      container: true,
      button: true,
      selected: selezionata,
      label: nome,
      hint: s.t(
        'Tocca due volte per selezionare questa categoria.',
        'Double tap to select this category.',
      ),
      onTap: selezionaCategoria,
      child: ExcludeSemantics(
        child: Material(
          color: selezionata ? categoria.sfondo : superficieVerde,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: selezionaCategoria,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 112),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selezionata ? categoria.colore : bordo,
                  width: selezionata ? 2.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(categoria.icona, color: categoria.colore, size: 30),
                      const Spacer(),
                      if (selezionata)
                        Icon(
                          Icons.check_circle_rounded,
                          color: categoria.colore,
                          size: 23,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    nome,
                    style: TextStyle(
                      color: testo,
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: selezionata
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selettoreGravita(Copie s) {
    const livelli = [
      ('bassa', 'Bassa', 'Low', verde),
      ('media', 'Media', 'Medium', Color.fromARGB(255, 208, 222, 21)),
      ('alta', 'Alta', 'High', Color.fromARGB(255, 236, 45, 45)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: livelli.map((livello) {
        final selezionata = _gravita == livello.$1;
        return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selezionata ? Icons.circle : Icons.circle_outlined,
                  size: 13,
                  color: livello.$4,
                ),
                const SizedBox(width: 7),
                Text(s.t(livello.$2, livello.$3)),
              ],
            ),
            selected: selezionata,
            showCheckmark: false,
            backgroundColor: superficieVerde,
            selectedColor: livello.$4.withValues(alpha: .14),
            side: BorderSide(
              color: selezionata ? livello.$4 : bordo,
              width: selezionata ? 1.5 : 1,
            ),
            onSelected: (_) => setState(() => _gravita = livello.$1),
          );
      }).toList(),
    );
  }

  Widget _passaggioProblema(Copie s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.t('Che problema hai notato?', 'What problem did you notice?'),
          style: const TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: testo,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          s.t(
            'Scegli la categoria che descrive meglio la situazione.',
            'Choose the category that best describes the situation.',
          ),
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: testoSecondario,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (builderContext, constraints) {
            final larghezza = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categorie
                  .map(
                    (categoria) => SizedBox(
                      width: larghezza,
                      child: _schedaCategoria(categoria, s),
                    ),
                  ) // 
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          s.t('Quanto è urgente?', 'How urgent is it?'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: testo,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.t(
            'Scegli un livello per aiutare a capire la priorità del problema.',
            'Choose a level to help show how urgent the issue is.',
          ),
          style: const TextStyle(fontSize: 13, color: testoSecondario),
        ),
        const SizedBox(height: 8),
        _selettoreGravita(s),
        const SizedBox(height: 16),
        Scheda(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: verde, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.t(
                    'La segnalazione è anonima. La posizione GPS è necessaria per inviarla; la fotografia è facoltativa.',
                    'The report is anonymous. GPS location is required to submit it; a photo is optional.',
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: testo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _schedaFunzioneInPreparazione({
    required IconData icona,
    required Color colore,
    required Color sfondoCard,
    required String titolo,
    required String descrizione,
    required String dettaglio,
  }) {
    return Scheda(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: sfondoCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icona, color: colore, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titolo,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: testo,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descrizione,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: testoSecondario,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
            decoration: BoxDecoration(
              color: sfondoCard.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: colore.withValues(alpha: .28)),
            ),
            child: Column(
              children: [
                Icon(icona, color: colore.withValues(alpha: .85), size: 35),
                const SizedBox(height: 8),
                Text(
                  dettaglio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: testoSecondario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.s.t('In preparazione', 'Coming soon'),
                    style: TextStyle(
                      fontSize: 13,
                      color: colore,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passaggioFotoLuogo(Copie s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('Aggiungiamo i dettagli', 'Add the details'), style: const TextStyle(fontSize: 23, height: 1.2, fontWeight: FontWeight.w800, color: testo)),
        const SizedBox(height: 7),
        Text(s.t('Allega una fotografia, se disponibile, e rileva il punto GPS del problema.', 'Attach a photo if available and get the GPS location of the issue.'), style: const TextStyle(fontSize: 16, height: 1.45, color: testoSecondario)),
        const SizedBox(height: 18),
        Scheda(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.add_a_photo_outlined, color: verde, size: 25),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('Fotografia del problema', 'Photo of the issue'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo))),
            ]),
            const SizedBox(height: 10),
            if (_foto != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(12), child: FutureBuilder<Uint8List>(future: _foto!.readAsBytes(), builder: (context, snapshot) => snapshot.hasData ? Image.memory(snapshot.data!, height: 150, width: double.infinity, fit: BoxFit.cover) : const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())))),
              const SizedBox(height: 8),
              Text(_foto!.name, style: const TextStyle(fontSize: 13, color: testoSecondario)),
            ] else
              Text(s.t('Nessuna fotografia selezionata. La foto è facoltativa.', 'No photo selected. A photo is optional.'), style: const TextStyle(fontSize: 14, color: testoSecondario)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => _selezionaFoto(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: Text(s.t('Fotocamera', 'Camera'))),
              OutlinedButton.icon(onPressed: () => _selezionaFoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(s.t('Galleria', 'Gallery'))),
              if (_foto != null) TextButton.icon(onPressed: () => setState(() => _foto = null), icon: const Icon(Icons.delete_outline), label: Text(s.t('Rimuovi', 'Remove'))),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Scheda(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.location_on_outlined, color: verdeProfondo, size: 25),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('Posizione del problema', 'Issue location'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: testo))),
            ]),
            const SizedBox(height: 8),
            Text(_posizione == null ? s.t('La posizione GPS è obbligatoria per inviare una segnalazione di problema.', 'GPS location is required to submit an issue report.') : 'GPS: ${_posizione!.latitude.toStringAsFixed(6)}, ${_posizione!.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _caricamentoGps ? null : _rilevaPosizione,
              icon: _caricamentoGps ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded),
              label: Text(_caricamentoGps ? s.t('Rilevamento...', 'Locating...') : s.t('Rileva posizione GPS', 'Get GPS location')),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        Text(s.t('La segnalazione può essere inviata solo se la posizione rientra nell’area del parco configurata.', 'The report can be submitted only if the location is within the configured park area.'), style: const TextStyle(fontSize: 13, height: 1.45, color: testoSecondario)),
      ],
    );
  }

  Widget _rigaRiepilogo(String titolo, String valore, IconData icona) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icona, color: verde, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            titolo,
            style: const TextStyle(fontSize: 14, color: testoSecondario),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            valore,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: testo,
            ),
          ),
        ),
      ],
    );
  }

  Widget _passaggioRiepilogo(Copie s) {
    final categoria = _categorie.firstWhere(
      (element) => element.id == _categoria,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.t('Ci siamo quasi!', 'Almost done!'),
          style: const TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: testo,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          s.t(
            'La descrizione è facoltativa. Controlla i dettagli prima di inviare la segnalazione.',
            'The description is optional. Review the details before submitting the report.',
          ),
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: testoSecondario,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          s.t('Descrizione (facoltativa)', 'Description (optional)'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: testo,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descrizione,
          minLines: 4,
          maxLines: 7,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: s.t(
              'Aggiungi dettagli utili, per esempio un punto di riferimento vicino…',
              'Add helpful details, such as a nearby landmark…',
            ),
            alignLabelWithHint: true,
            helperText: s.t(
              'Non inserire dati personali.',
              'Do not include personal information.',
            ),
          ),
        ),
        const SizedBox(height: 18),
        Scheda(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined, color: verde, size: 25),
                  const SizedBox(width: 10),
                  Text(
                    s.t('Riepilogo', 'Review'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: testo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _rigaRiepilogo(
                s.t('Categoria', 'Category'),
                s.t(categoria.nomeIt, categoria.nomeEn),
                categoria.icona,
              ),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Gravità', 'Severity'),
                s.t(
                  _gravita == 'bassa'
                      ? 'Bassa'
                      : _gravita == 'media'
                      ? 'Media'
                      : 'Alta',
                  _gravita == 'bassa'
                      ? 'Low'
                      : _gravita == 'media'
                      ? 'Medium'
                      : 'High',
                ),
                Icons.flag_outlined,
              ),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Fotografia', 'Photo'),
                _foto?.name ?? s.t('Facoltativa', 'Optional'),
                Icons.photo_outlined,
              ),
              const Divider(height: 22),
              _rigaRiepilogo(
                s.t('Posizione', 'Location'),
                _posizione == null ? s.t('Non rilevata', 'Not detected') : '${_posizione!.latitude.toStringAsFixed(4)}, ${_posizione!.longitude.toStringAsFixed(4)}',
                Icons.location_on_outlined,
              ),
              if (_descrizione.text.trim().isNotEmpty) ...[
                const Divider(height: 22),
                Text(
                  s.t('Descrizione', 'Description'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: testoSecondario,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _descrizione.text.trim(),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: testo,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            s.t(
              'La segnalazione verrà inviata al server quando premi Completa.',
              'The report will be sent to the server when you tap Finish.',
            ),
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: testoSecondario,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;

    return ContenitorePagina(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitoloPagina(
            titolo: s.t('Segnala un problema', 'Report a problem'),
            descrizione: s.t(
              'Il tuo aiuto rende il parco un posto migliore.',
              'Your help makes Park a better place.',
            ),
            colore: verdeMedio,
          ),
          Scheda(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _indicatorePassaggi(s),
                const SizedBox(height: 19),
                AnimatedSwitcher(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey<int>(_passaggio),
                    child: _passaggio == 0
                        ? _passaggioProblema(s)
                        : _passaggio == 1
                        ? _passaggioFotoLuogo(s)
                        : _passaggioRiepilogo(s),
                  ),
                ),
                if (_errore != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: verdePallido,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: verdeMedio),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: verdeMedio,
                            size: 22,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _errore!,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: testo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, vincoli) {
                    final testoIngrandito =
                        MediaQuery.textScalerOf(context).scale(16) > 18;
                    final impilaPulsanti = _passaggio > 0 &&
                        (vincoli.maxWidth < 340 || testoIngrandito);
                    final pulsanteIndietro = SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _tornaIndietro,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: Text(s.t('Indietro', 'Back')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: verde,
                          minimumSize: const Size(0, 56),
                          side: const BorderSide(color: verde, width: 1.5),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                    final pulsanteAvanti = SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _invioInCorso ? null : _vaiAvanti,
                        icon: Icon(
                          _invioInCorso ? Icons.hourglass_top_rounded : _passaggio == 2
                              ? Icons.check_circle_outline_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(
                          s.t(
                            _invioInCorso ? 'Invio...' : _passaggio == 2 ? 'Completa' : 'Continua',
                            _invioInCorso ? 'Sending...' : _passaggio == 2 ? 'Finish' : 'Continue',
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: verde,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );

                    if (_passaggio == 0) {
                      return SizedBox(
                        width: double.infinity,
                        child: pulsanteAvanti,
                      );
                    }
                    if (impilaPulsanti) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pulsanteIndietro,
                          const SizedBox(height: 10),
                          pulsanteAvanti,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: pulsanteIndietro),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: pulsanteAvanti),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  s.t(
                    'Puoi tornare indietro e modificare le tue scelte prima dell’invio.',
                    'You can go back and change your choices before submitting.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: testoSecondario,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: s.t('Informazione sulla privacy', 'Privacy information'),
            child: Text(
              s.t(
                'La segnalazione viene inviata in forma anonima al backend del parco.',
                'The report is submitted anonymously to the park backend.',
              ),
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: testoSecondario,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriaSegnalazione {
  final String id;
  final String nomeIt;
  final String nomeEn;
  final IconData icona;
  final Color colore;
  final Color sfondo;

  const _CategoriaSegnalazione({
    required this.id,
    required this.nomeIt,
    required this.nomeEn,
    required this.icona,
    required this.colore,
    required this.sfondo,
  });
}

class _IdeaItem {
  final int id;
  final String title;
  final String description;
  final int votes;
  final bool votedByMe;
  final DateTime createdAt;

  const _IdeaItem({required this.id, required this.title, required this.description, required this.votes, required this.votedByMe, required this.createdAt});

  factory _IdeaItem.fromJson(Map<String, dynamic> json) => _IdeaItem(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    votes: json['vote_count'] as int? ?? 0,
    votedByMe: json['voted_by_me'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
  );

  String get dateLabel => '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}';
}

class SchermataIdee extends StatefulWidget {
  final Copie s;
  const SchermataIdee({super.key, required this.s});
  @override
  State<SchermataIdee> createState() => _SchermataIdeeState();
}

class _SchermataIdeeState extends State<SchermataIdee> {
  String _filtroIdee = 'recenti';
  bool _ideaPrivata = false;
  bool _caricamento = true;
  bool _invio = false;
  String? _errore;
  int? _operazioneIdea;
  List<_IdeaItem> _idee = [];
  final TextEditingController _titolo = TextEditingController();
  final TextEditingController _dettagli = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_caricaIdee());
  }

  @override
  void dispose() {
    _titolo.dispose();
    _dettagli.dispose();
    super.dispose();
  }

  Future<void> _caricaIdee() async {
    if (mounted) setState(() { _caricamento = true; _errore = null; });
    try {
      final result = await CitizenApi.instance.getIdeas(sort: _filtroIdee == 'votate' ? 'votes' : 'recent');
      final rows = (result['items'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _idee = rows.map(_IdeaItem.fromJson).toList(); _caricamento = false; });
    } catch (e) {
      if (mounted) setState(() { _errore = e.toString(); _caricamento = false; });
    }
  }

  Future<void> _toggleVote(_IdeaItem idea) async {
    setState(() => _operazioneIdea = idea.id);
    try {
      if (idea.votedByMe) {
        await CitizenApi.instance.removeIdeaVote(idea.id);
      } else {
        await CitizenApi.instance.voteIdea(idea.id);
      }
      await _caricaIdee();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _operazioneIdea = null);
    }
  }

  Future<void> _mostraAnteprima(Copie s) async {
    final titolo = _titolo.text.trim();
    final dettagli = _dettagli.text.trim();
    if (titolo.length < 3 || dettagli.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('Inserisci un titolo di almeno 3 caratteri e una descrizione di almeno 10.', 'Enter a title of at least 3 characters and a description of at least 10.'))));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('Anteprima del suggerimento', 'Suggestion preview')),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s.t('Titolo', 'Title'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4), Text(titolo),
          const SizedBox(height: 12),
          Text(s.t('Dettagli', 'Details'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4), Text(dettagli),
          const SizedBox(height: 12),
          Text(s.t('Visibilità: ', 'Visibility: ') + (_ideaPrivata ? s.t('Privata', 'Private') : s.t('Pubblica', 'Public')), style: const TextStyle(fontWeight: FontWeight.w700)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s.t('Modifica', 'Edit'))),
          FilledButton(onPressed: _invio ? null : () { Navigator.of(dialogContext).pop(); unawaited(_inviaIdea(s)); }, child: Text(s.t('Invia idea', 'Submit idea'))),
        ],
      ),
    );
  }

  Future<void> _inviaIdea(Copie s) async {
    final titolo = _titolo.text.trim();
    final dettagli = _dettagli.text.trim();
    if (titolo.length < 3 || dettagli.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('Titolo o descrizione troppo brevi.', 'Title or description is too short.'))));
      return;
    }
    setState(() { _invio = true; });
    try {
      await CitizenApi.instance.createIdea(title: titolo, description: dettagli, isPrivate: _ideaPrivata);
      _titolo.clear();
      _dettagli.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ideaPrivata ? s.t('Idea inviata ai gestori del parco.', 'Idea sent to park managers.') : s.t('Idea pubblicata.', 'Idea published.'))));
      }
      await _caricaIdee();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _invio = false);
    }
  }

  Widget _schedaIdea(_IdeaItem idea, Copie s) {
    final votata = idea.votedByMe;
    final busy = _operazioneIdea == idea.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Scheda(
        padding: const EdgeInsets.all(15), colore: const Color(0xFFF7F1E5), coloreBordo: const Color(0xFFA18A62),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: verdePallido, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.lightbulb_outline_rounded, color: verdeMedio)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(idea.title, style: const TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w800, color: testo)),
              const SizedBox(height: 5),
              Text(idea.description, style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario)),
            ])),
          ]),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
            Text(idea.dateLabel, style: const TextStyle(fontSize: 13, color: testoSecondario)),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
              Text('${idea.votes} ${s.t('voti', 'votes')}', style: TextStyle(fontWeight: FontWeight.w800, color: votata ? verde : testoSecondario)),
              votata
                ? FilledButton.tonalIcon(onPressed: busy ? null : () => _toggleVote(idea), icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.thumb_up_rounded, size: 18), label: Text(s.t('Rimuovi', 'Remove')), style: FilledButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: verde, backgroundColor: verdeChiaro, padding: const EdgeInsets.symmetric(horizontal: 12)))
                : OutlinedButton.icon(onPressed: busy ? null : () => _toggleVote(idea), icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.thumb_up_outlined, size: 18), label: Text(s.t('Mi piace', 'Upvote')), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: verde, side: const BorderSide(color: verde), padding: const EdgeInsets.symmetric(horizontal: 12))),
            ]),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ContenitorePagina(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitoloPagina(titolo: s.t('Idee per il parco', 'Ideas for the park'), descrizione: s.t('Proponi un miglioramento e scegli se renderlo visibile a tutti.', 'Suggest an improvement and choose whether it is visible to everyone.'), colore: verdeAccento),
      const SizedBox(height: 4),
      Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF244B35), Color(0xFF527A50)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x1A17271D), blurRadius: 16, offset: Offset(0, 5))]), child: Row(children: [const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 34), const SizedBox(width: 13), Expanded(child: Text(s.t('Ogni idea può far crescere qualcosa di bello.', 'Every idea can help something good grow.'), style: const TextStyle(fontSize: 15, height: 1.35, color: Colors.white, fontWeight: FontWeight.w700)))])),
      const SizedBox(height: 18),
      Scheda(padding: const EdgeInsets.all(16), colore: const Color(0xFFFFFDF7), coloreBordo: const Color(0xFF9BAA8D), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('La tua idea', 'Your idea'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo)),
        const SizedBox(height: 4),
        Text(s.t('Ogni proposta è benvenuta: raccontaci cosa migliorerebbe il parco.', 'Every suggestion is welcome: tell us what could make the park better.'), style: const TextStyle(fontSize: 14, height: 1.4, color: testoSecondario)),
        const SizedBox(height: 14),
        TextField(controller: _titolo, textCapitalization: TextCapitalization.sentences, maxLength: 120, decoration: InputDecoration(labelText: s.t('Titolo', 'Title'), hintText: s.t('Es. Più ombra vicino all’area giochi', 'E.g. More shade near the playground'))),
        const SizedBox(height: 12),
        TextField(controller: _dettagli, minLines: 3, maxLines: 4, maxLength: 1000, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: s.t('Descrizione', 'Description'), hintText: s.t('Descrivi la tua idea in poche parole…', 'Describe your idea in a few words…'), alignLabelWithHint: true)),
        const SizedBox(height: 16),
        Text(s.t('Chi può vedere questa idea?', 'Who can see this idea?'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: testo)),
        const SizedBox(height: 8),
        SegmentedButton<bool>(segments: [ButtonSegment<bool>(value: false, icon: const Icon(Icons.public_rounded), label: Text(s.t('Pubblica', 'Public'))), ButtonSegment<bool>(value: true, icon: const Icon(Icons.lock_outline_rounded), label: Text(s.t('Privata', 'Private')))], selected: {_ideaPrivata}, showSelectedIcon: false, onSelectionChanged: (valori) => setState(() => _ideaPrivata = valori.first)),
        const SizedBox(height: 8),
        Text(s.t('Pubblica: visibile alla comunità. Privata: destinata ai gestori del parco.', 'Public: visible to the community. Private: intended for park managers.'), style: const TextStyle(fontSize: 13, height: 1.4, color: testoSecondario)),
        const SizedBox(height: 14),
        PulsanteAzione(testo: _invio ? s.t('Invio in corso...', 'Submitting...') : s.t('Rivedi e invia', 'Review and submit'), icona: Icons.preview_rounded, colore: verdeScuro, onPressed: _invio ? null : () => _mostraAnteprima(s)),
      ])),
      const SizedBox(height: 22),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [Text(s.t('Idee della comunità', 'Community ideas'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: testo)), Text('${_idee.length} ${s.t('idee', 'ideas')}', style: const TextStyle(fontSize: 13, color: testoSecondario, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 5),
      Text(s.t('Esprimi il tuo interesse con un voto.', 'Show your support with an upvote.'), style: const TextStyle(fontSize: 14, color: testoSecondario)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: Text(s.t('Più recenti', 'Most recent')), selected: _filtroIdee == 'recenti', selectedColor: verdeChiaro, onSelected: (_) { setState(() => _filtroIdee = 'recenti'); unawaited(_caricaIdee()); }),
        ChoiceChip(label: Text(s.t('Più votate', 'Most voted')), selected: _filtroIdee == 'votate', selectedColor: verdeChiaro, onSelected: (_) { setState(() => _filtroIdee = 'votate'); unawaited(_caricaIdee()); }),
      ]),
      const SizedBox(height: 8),
      if (_caricamento) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
      else if (_errore != null) Scheda(child: Column(children: [Text(_errore!, style: const TextStyle(color: testoSecondario)), TextButton(onPressed: _caricaIdee, child: Text(s.t('Riprova', 'Retry')))]))
      else if (_idee.isEmpty) Scheda(child: Text(s.t('Non ci sono ancora idee pubbliche. Puoi essere il primo a proporne una.', 'There are no public ideas yet. You can be the first to suggest one.'), style: const TextStyle(fontSize: 14, color: testoSecondario)))
      else ..._idee.map((idea) => _schedaIdea(idea, s)),
      Padding(padding: const EdgeInsets.only(top: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, size: 18, color: verde), const SizedBox(width: 8), Expanded(child: Text(s.t('I voti indicano l’interesse della comunità, non garantiscono che un’idea venga realizzata.', 'Votes show community interest; they do not guarantee an idea will be implemented.'), style: const TextStyle(fontSize: 13, height: 1.4, color: testoSecondario)))])),
    ]));
  }
}

class Avviso {
  final String categoria;
  final String? statoManutenzione;
  final IconData icona;
  final Color colore;
  final String titoloIt;
  final String titoloEn;
  final String descrizioneIt;
  final String descrizioneEn;
  final String data;

  const Avviso({
    required this.categoria,
    this.statoManutenzione,
    required this.icona,
    required this.colore,
    required this.titoloIt,
    required this.titoloEn,
    required this.descrizioneIt,
    required this.descrizioneEn,
    required this.data,
  });
}

class SchermataAvvisi extends StatefulWidget {
  final Copie s;
  const SchermataAvvisi({super.key, required this.s});

  @override
  State<SchermataAvvisi> createState() => _SchermataAvvisiState();
}

class _SchermataAvvisiState extends State<SchermataAvvisi> {
  String _filtro = 'tutti';
  List<Avviso> _avvisi = [];
  bool _caricamento = true;
  String? _errore;

  @override
  void initState() {
    super.initState();
    unawaited(_caricaAvvisi());
  }

  Future<void> _caricaAvvisi() async {
    if (mounted) setState(() { _caricamento = true; _errore = null; });
    try {
      final rows = await CitizenApi.instance.getNotices();
      final parsed = rows.map((item) {
        final level = item['level'] as String? ?? 'info';
        final category = level == 'alert' ? 'importante' : level == 'warning' ? 'manutenzione' : 'novita';
        final date = DateTime.tryParse(item['starts_at']?.toString() ?? '')?.toLocal();
        final dateLabel = date == null ? '' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
        return Avviso(
          categoria: category,
          icona: level == 'alert' ? Icons.priority_high_rounded : level == 'warning' ? Icons.handyman_rounded : Icons.new_releases_rounded,
          colore: level == 'alert' ? const Color(0xFFB42318) : level == 'warning' ? const Color(0xFF8A5A00) : const Color(0xFF145A86),
          titoloIt: item['title'] as String? ?? '',
          titoloEn: item['title'] as String? ?? '',
          descrizioneIt: item['body'] as String? ?? '',
          descrizioneEn: item['body'] as String? ?? '',
          data: dateLabel,
        );
      }).toList();
      if (mounted) setState(() { _avvisi = parsed; _caricamento = false; });
    } catch (e) {
      if (mounted) setState(() { _errore = e.toString(); _caricamento = false; });
    }
  }

  Widget _filtroAvvisi(String valore, String etichetta) {
    final selezionato = _filtro == valore;
    return ChoiceChip(
      label: Text(etichetta),
      selected: selezionato,
      selectedColor: verdeChiaro,
      backgroundColor: superficieVerde,
      side: BorderSide(color: selezionato ? verde : bordo),
      onSelected: (_) => setState(() => _filtro = valore),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final elenco = _avvisi
        .where((avviso) => _filtro == 'tutti' || avviso.categoria == _filtro)
        .toList();
    if (_filtro == 'tutti') {
      elenco.sort(
        (a, b) => (b.categoria == 'importante' ? 1 : 0).compareTo(
          a.categoria == 'importante' ? 1 : 0,
        ),
      );
    }

    return ContenitorePagina(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitoloPagina(
            titolo: s.t('Avvisi del parco', 'Park notices'),
            descrizione: s.t(
              'Qui trovi comunicazioni, avvisi importanti e aggiornamenti sulla manutenzione.',
              'Find park news, important notices and maintenance updates here.',
            ),
            colore: verdePrincipale,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _filtroAvvisi('tutti', s.t('Tutti', 'All')),
              _filtroAvvisi('importante', s.t('Importanti', 'Important')),
              _filtroAvvisi('manutenzione', s.t('Manutenzione', 'Maintenance')),
              _filtroAvvisi('novita', s.t('Novità', 'News')),
            ],
          ),
          const SizedBox(height: 16),
          if (_caricamento)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_errore != null)
            Scheda(child: Column(children: [Text(_errore!, style: const TextStyle(color: testoSecondario)), TextButton(onPressed: _caricaAvvisi, child: Text(s.t('Riprova', 'Retry')))]))
          else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  s.t('Aggiornamenti', 'Updates'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: testo,
                  ),
                ),
              ),
              Text(
                '${elenco.length} ${s.t('elementi', 'items')}',
                style: const TextStyle(fontSize: 13, color: testoSecondario),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (elenco.isEmpty)
            Scheda(
              child: Text(
                s.t(
                  'Non ci sono aggiornamenti in questa categoria.',
                  'There are no updates in this category.',
                ),
                style: const TextStyle(fontSize: 14, color: testoSecondario),
              ),
            )
          else
            ...elenco.map(
              (avviso) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Scheda(
                  colore: avviso.categoria == 'importante'
                      ? const Color(0xFFFDECEC)
                      : avviso.categoria == 'novita'
                          ? const Color(0xFFEAF4FB)
                          : avviso.statoManutenzione == 'segnalata'
                              ? const Color(0xFFFFF3E8)
                              : avviso.statoManutenzione == 'in_corso'
                                  ? const Color(0xFFFFF8E1)
                                  : const Color(0xFFEAF0E3),
                  coloreBordo: avviso.colore,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: avviso.colore.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              avviso.icona,
                              color: avviso.colore,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 5,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: avviso.colore,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Text(
                                      _etichettaCategoria(
                                        s,
                                        avviso.categoria,
                                        avviso.statoManutenzione,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: avviso.colore,
                                      ),
                                    ),
                                    if (avviso.categoria == 'importante')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFDECEC),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(0xFFB42318),
                                          ),
                                        ),
                                        child: Text(
                                          s.t('DA LEGGERE', 'PLEASE READ'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFB42318),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    avviso.data,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: testoSecondario,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.t(avviso.titoloIt, avviso.titoloEn),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: testo,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.t(avviso.descrizioneIt, avviso.descrizioneEn),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: testoSecondario,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            s.t(
              'Gli avvisi sono informazioni pubbliche del parco.',
              'Notices are public park information.',
            ),
            style: const TextStyle(fontSize: 13, color: testoSecondario),
          ),
          ],
        ],
      ),
    );
  }
}

String _etichettaCategoria(
  Copie s,
  String categoria,
  String? statoManutenzione,
) {
  switch (categoria) {
    case 'importante':
      return s.t('Avviso importante', 'Important notice');
    case 'novita':
      return s.t('Novità', 'News');
    case 'manutenzione':
      switch (statoManutenzione) {
        case 'segnalata':
          return s.t('Manutenzione segnalata', 'Maintenance reported');
        case 'in_corso':
          return s.t('Manutenzione in corso', 'Maintenance in progress');
        case 'completata':
          return s.t('Manutenzione completata', 'Maintenance completed');
      }
      return s.t('Manutenzione', 'Maintenance');
    default:
      return s.t('Aggiornamento', 'Update');
  }
}
