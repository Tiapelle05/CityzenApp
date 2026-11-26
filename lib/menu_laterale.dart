import 'package:flutter/material.dart';

import 'ui.dart';

/// Barra laterale a scomparsa: collegamento, scorciatoie, impostazioni e
/// informazioni. Tiene libera la barra in alto, dove restano solo menu,
/// marchio e campanella.
class MenuLaterale extends StatelessWidget {
  final Copie s;
  final bool inglese;
  final ValueChanged<bool> onLingua;

  /// Profilo attivo e passaggio demo ⇄ server (null: non si può cambiare).
  final bool demo;
  final String server;
  final bool cambioInCorso;
  final ValueChanged<bool>? onProfilo;
  final VoidCallback? onCambiaServer;

  final VoidCallback onMie;
  final VoidCallback onIdee;
  final VoidCallback onAvvisi;
  final int avvisiAttivi;
  final bool avvisiUrgenti;

  /// Tema scelto (null: segue il telefono) e cambio del tema.
  final ThemeMode tema;
  final ValueChanged<ThemeMode>? onTema;

  const MenuLaterale({
    super.key,
    required this.s,
    required this.inglese,
    required this.onLingua,
    required this.demo,
    required this.server,
    this.cambioInCorso = false,
    this.onProfilo,
    this.onCambiaServer,
    required this.onMie,
    required this.onIdee,
    required this.onAvvisi,
    this.avvisiAttivi = 0,
    this.avvisiUrgenti = false,
    this.tema = ThemeMode.system,
    this.onTema,
  });

  /// Chiude il menu e poi esegue l'azione (le pagine si aprono sopra le schede).
  VoidCallback _chiudiE(BuildContext context, VoidCallback azione) => () {
        Navigator.of(context).pop();
        azione();
      };

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: sfondo,
      surfaceTintColor: Colors.transparent,
      width: 312,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(margineLaterale, 12, margineLaterale, 24),
          children: [
            _marchio(),
            const SizedBox(height: 20),
            _collegamento(context),
            _titolo(s.t('Le tue cose', 'Your stuff')),
            _gruppo([
              _voce(
                icona: Icons.receipt_long_rounded,
                accento: Accento.arancio,
                etichetta: s.t('Le mie segnalazioni', 'My reports'),
                onTap: _chiudiE(context, onMie),
              ),
              _voce(
                icona: Icons.lightbulb_rounded,
                accento: Accento.giallo,
                etichetta: s.t('Idee per il parco', 'Ideas for the park'),
                onTap: _chiudiE(context, onIdee),
              ),
              _voce(
                icona: Icons.notifications_rounded,
                accento: Accento.blu,
                etichetta: s.t('Avvisi del parco', 'Park notices'),
                coda: avvisiAttivi == 0
                    ? null
                    : Etichetta('$avvisiAttivi', colore: avvisiUrgenti ? coralloScuro : cieloScuro),
                onTap: _chiudiE(context, onAvvisi),
              ),
            ]),
            _titolo(s.t('Impostazioni', 'Settings')),
            _gruppo([
              _impostazione(
                icona: Icons.translate_rounded,
                etichetta: s.t('Lingua', 'Language'),
                controllo: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: _stileSegmenti,
                  segments: const [
                    ButtonSegment(value: false, label: Text('IT'), tooltip: 'Italiano'),
                    ButtonSegment(value: true, label: Text('EN'), tooltip: 'English'),
                  ],
                  selected: {inglese},
                  onSelectionChanged: (v) => onLingua(v.first),
                ),
              ),
              if (onTema != null)
                _impostazione(
                  icona: Icons.contrast_rounded,
                  etichetta: s.t('Tema', 'Theme'),
                  sotto: true,
                  controllo: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: _stileSegmenti,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_rounded, size: 18),
                        label: Text(s.t('Chiaro', 'Light')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_rounded, size: 18),
                        label: Text(s.t('Scuro', 'Dark')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                        label: Text(s.t('Auto', 'Auto')),
                        tooltip: s.t('Come il telefono', 'Same as the phone'),
                      ),
                    ],
                    selected: {tema},
                    onSelectionChanged: (v) => onTema!(v.first),
                  ),
                ),
            ]),
            _titolo(s.t('Informazioni', 'About')),
            _gruppo([
              _voce(
                icona: Icons.help_outline_rounded,
                etichetta: s.t('Come funziona', 'How it works'),
                onTap: () => _comeFunziona(context),
              ),
              _voce(
                icona: Icons.shield_outlined,
                etichetta: s.t('Privacy e anonimato', 'Privacy and anonymity'),
                onTap: () => _privacy(context),
              ),
              _voce(
                icona: Icons.emergency_outlined,
                accento: Accento.arancio,
                etichetta: s.t('Emergenze · 112', 'Emergencies · 112'),
                onTap: () => _emergenze(context),
              ),
              _voce(
                icona: Icons.info_outline_rounded,
                etichetta: s.t('Informazioni sull’app', 'About the app'),
                onTap: () => _informazioni(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _stileSegmenti = SegmentedButton.styleFrom(
    minimumSize: const Size(0, 40),
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
  );

  Widget _marchio() => Row(
        children: [
          Image.asset('Assets/logo_treeyes.png', height: 44, semanticLabel: 'Treeyes_Cityzen'),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Treeyes',
                style: TextStyle(fontSize: 24, height: 1.05, fontWeight: FontWeight.w800, color: forestaScura, letterSpacing: -.4),
              ),
              Text(
                'CITYZEN',
                style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w800, color: foresta, letterSpacing: 2.2),
              ),
            ],
          ),
        ],
      );

  /// Riquadro del collegamento: dove sono i dati e il passaggio all'altro profilo.
  Widget _collegamento(BuildContext context) {
    final accento = demo ? Accento.viola : Accento.verde;
    final altro = demo ? 'Server' : 'Demo';
    return Scheda(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconaTonda(
                demo ? Icons.science_rounded : Icons.cloud_done_rounded,
                colore: accento.forte,
                sfondo: accento.tinta,
                dimensione: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demo ? s.t('Modalità demo', 'Demo mode') : s.t('Collegato al server', 'Connected to the server'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: testo),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      demo ? s.t('Dati simulati, nulla viene inviato', 'Simulated data, nothing is sent') : server,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: testoSecondario),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onProfilo != null || onCambiaServer != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onProfilo != null)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: cambioInCorso ? null : () => onProfilo!(!demo),
                      icon: cambioInCorso
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.swap_horiz_rounded, size: 19),
                      label: Text(s.t('Passa a $altro', 'Switch to $altro'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (onCambiaServer != null)
                  IconButton(
                    tooltip: s.t('Cambia server', 'Change server'),
                    onPressed: _chiudiE(context, onCambiaServer!),
                    icon: const Icon(Icons.dns_outlined, color: testoSecondario),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _titolo(String testoTitolo) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
        child: Semantics(
          header: true,
          child: Text(
            testoTitolo.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: testoSecondario, letterSpacing: 1.1),
          ),
        ),
      );

  /// Voci raggruppate in un'unica scheda, separate da righe sottili.
  Widget _gruppo(List<Widget> voci) => Scheda(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, v) in voci.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 58),
              v,
            ],
          ],
        ),
      );

  Widget _voce({
    required IconData icona,
    required String etichetta,
    required VoidCallback onTap,
    Accento? accento,
    Widget? coda,
  }) =>
      ListTile(
        onTap: onTap,
        minTileHeight: 52,
        contentPadding: const EdgeInsets.only(left: 14, right: 10),
        leading: Icon(icona, color: accento?.forte ?? testoSecondario, size: 22),
        title: Text(etichetta, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: testo)),
        trailing: coda ?? const Icon(Icons.chevron_right_rounded, color: testoTenue),
      );

  /// Riga di impostazione: etichetta e controllo accanto, o sotto se [sotto].
  Widget _impostazione({required IconData icona, required String etichetta, required Widget controllo, bool sotto = false}) {
    final riga = Row(
      children: [
        Icon(icona, color: testoSecondario, size: 22),
        const SizedBox(width: 16),
        Expanded(child: Text(etichetta, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: testo))),
        if (!sotto) controllo,
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: sotto
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [riga, const SizedBox(height: 10), controllo],
            )
          : riga,
    );
  }

  Future<void> _finestra(BuildContext context, IconData icona, Accento accento, String titolo, List<String> paragrafi) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: IconaTonda(icona, colore: accento.forte, sfondo: accento.tinta, dimensione: 52),
          title: Text(titolo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, p) in paragrafi.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Text(p, style: const TextStyle(fontSize: 14.5, height: 1.45, color: testo)),
                ],
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('Ho capito', 'Got it')))],
        ),
      );

  void _comeFunziona(BuildContext context) => _finestra(context, Icons.help_outline_rounded, Accento.verde,
      s.t('Come funziona', 'How it works'), [
        s.t('1. Vedi un problema nel parco? Tocca «Segnala», scegli cosa hai notato e conferma la posizione.',
            '1. Spotted a problem in the park? Tap “Report”, choose what you noticed and confirm the location.'),
        s.t('2. Il personale del parco la riceve e la prende in carico: lo stato si aggiorna da solo.',
            '2. Park staff receive it and take care of it: the status updates by itself.'),
        s.t('3. Segui le tue segnalazioni sulla mappa e chiedi a Parky qualsiasi cosa sul parco.',
            '3. Follow your reports on the map and ask Parky anything about the park.'),
      ]);

  void _privacy(BuildContext context) => _finestra(context, Icons.shield_outlined, Accento.verde,
      s.t('Privacy e anonimato', 'Privacy and anonymity'), [
        s.t('Le segnalazioni sono anonime: non chiediamo il tuo nome.',
            'Reports are anonymous: we do not ask for your name.'),
        s.t('La posizione delle segnalazioni degli altri non è pubblica: sulla mappa vedi solo le tue.',
            'Other people’s report locations are not public: on the map you only see yours.'),
        s.t('Non fotografare persone e non scrivere dati personali nelle descrizioni.',
            'Do not photograph people or write personal data in descriptions.'),
      ]);

  void _emergenze(BuildContext context) => _finestra(context, Icons.emergency_outlined, Accento.arancio,
      s.t('In caso di emergenza', 'In an emergency'), [
        s.t('Per pericoli immediati per persone o cose chiama subito il 112, il numero unico di emergenza.',
            'For immediate danger to people or property call 112, the single emergency number, right away.'),
        s.t('Le segnalazioni dell’app non sostituiscono i servizi di emergenza.',
            'App reports do not replace emergency services.'),
      ]);

  void _informazioni(BuildContext context) => showAboutDialog(
        context: context,
        applicationName: 'Treeyes Cityzen',
        applicationIcon: Image.asset('Assets/logo_treeyes.png', height: 48),
        children: [
          Text(
            s.t('Mappa © OpenStreetMap contributors.', 'Map © OpenStreetMap contributors.'),
            style: const TextStyle(fontSize: 13.5, color: testoSecondario),
          ),
        ],
      );
}
