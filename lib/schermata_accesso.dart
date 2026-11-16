import 'package:flutter/material.dart';

import 'citizen_api.dart';
import 'ui.dart';

/// Pagina di accesso: si sceglie se collegarsi a un server reale (indirizzo IP
/// del computer con il backend) oppure provare l'app con i dati simulati.
class SchermataAccesso extends StatefulWidget {
  final Copie s;
  final ValueChanged<bool> onLinguaCambiata;
  /// Chiamata quando il collegamento (server o demo) è pronto.
  final VoidCallback onCollegato;

  const SchermataAccesso({
    super.key,
    required this.s,
    required this.onLinguaCambiata,
    required this.onCollegato,
  });

  @override
  State<SchermataAccesso> createState() => _SchermataAccessoState();
}

class _SchermataAccessoState extends State<SchermataAccesso> {
  late final TextEditingController _indirizzo = TextEditingController(text: _indirizzoBreve(CitizenApi.instance.serverSalvato));
  bool _inCorso = false;
  bool _demoInCorso = false;
  String? _errore;

  /// Mostra l'indirizzo salvato in forma corta («192.168.1.20» invece di «http://192.168.1.20:8000»).
  static String _indirizzoBreve(String? url) {
    if (url == null) return '';
    return url.replaceFirst('http://', '').replaceFirst(RegExp(r':8000$'), '');
  }

  @override
  void dispose() {
    _indirizzo.dispose();
    super.dispose();
  }

  Future<void> _collegati() async {
    final s = widget.s;
    FocusScope.of(context).unfocus();
    final url = CitizenApi.normalizzaServer(_indirizzo.text);
    if (url == null) {
      setState(() => _errore = s.t('Scrivi l’indirizzo IP del server, per esempio 192.168.1.20.', 'Enter the server IP address, for example 192.168.1.20.'));
      return;
    }
    setState(() {
      _inCorso = true;
      _errore = null;
    });
    try {
      await CitizenApi.verificaServer(url);
      await CitizenApi.instance.collegaServer(url);
      if (mounted) widget.onCollegato();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errore = CitizenApi.instance.initializationError ?? e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  Future<void> _provaDemo() async {
    setState(() {
      _demoInCorso = true;
      _errore = null;
    });
    await CitizenApi.instance.setDemoMode(true);
    if (mounted) widget.onCollegato();
  }

  Widget _logo() => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [forestaScura, foglia], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x4017694A), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: const Icon(Icons.park_rounded, color: Colors.white, size: 40),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final anteprima = CitizenApi.normalizzaServer(_indirizzo.text);
    final occupato = _inCorso || _demoInCorso;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => widget.onLinguaCambiata(!s.inglese),
                      icon: const Icon(Icons.translate_rounded, size: 18),
                      label: Text(s.inglese ? 'Italiano' : 'English'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: _logo()),
                  const SizedBox(height: 18),
                  const Text(
                    'Treeyes',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: forestaScura, letterSpacing: -.6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.t('Segnala i problemi del parco e segui come vengono risolti.', 'Report park problems and follow how they get fixed.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.45, color: testoSecondario),
                  ),
                  const SizedBox(height: 28),
                  Scheda(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          const IconaTonda(Icons.dns_rounded, colore: foresta, sfondo: menta, dimensione: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.t('Collegati al server', 'Connect to the server'),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: testo),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _indirizzo,
                          enabled: !occupato,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          textInputAction: TextInputAction.go,
                          onChanged: (_) => setState(() => _errore = null),
                          onSubmitted: (_) => _collegati(),
                          decoration: InputDecoration(
                            labelText: s.t('Indirizzo IP del server', 'Server IP address'),
                            hintText: s.t('es. 192.168.1.20', 'e.g. 192.168.1.20'),
                            prefixIcon: const Icon(Icons.lan_outlined),
                            helperText: anteprima == null
                                ? s.t('La porta 8000 si aggiunge da sola.', 'Port 8000 is added automatically.')
                                : s.t('Mi collegherò a $anteprima', 'Will connect to $anteprima'),
                            helperMaxLines: 2,
                          ),
                        ),
                        AnimatedSize(
                          duration: durata(context, 220),
                          child: _errore == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Riquadro(icona: Icons.error_outline_rounded, messaggio: _errore!, accento: Accento.arancio),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: occupato ? null : _collegati,
                            style: FilledButton.styleFrom(
                              backgroundColor: foresta,
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            icon: _inCorso
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.login_rounded),
                            label: Text(_inCorso ? s.t('Collegamento…', 'Connecting…') : s.t('Collegati', 'Connect')),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 4),
                            leading: const Icon(Icons.help_outline_rounded, color: testoSecondario),
                            title: Text(
                              s.t('Come trovo l’indirizzo?', 'How do I find the address?'),
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: testoSecondario),
                            ),
                            children: [
                              Text(
                                s.t(
                                  '1. Avvia il backend con Docker sul computer.\n'
                                      '2. Sul computer apri il terminale e scrivi «ipconfig» (Windows) o «ip addr» (Linux/macOS): '
                                      'usa l’indirizzo IPv4 della scheda Wi-Fi, per esempio 192.168.1.20.\n'
                                      '3. Il telefono deve essere sulla stessa rete Wi-Fi del computer.',
                                  '1. Start the backend with Docker on the computer.\n'
                                      '2. On the computer open a terminal and run “ipconfig” (Windows) or “ip addr” (Linux/macOS): '
                                      'use the Wi-Fi adapter’s IPv4 address, for example 192.168.1.20.\n'
                                      '3. The phone must be on the same Wi-Fi network as the computer.',
                                ),
                                style: const TextStyle(fontSize: 13.5, height: 1.5, color: testoSecondario),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(s.t('oppure', 'or'), style: const TextStyle(color: testoSecondario, fontWeight: FontWeight.w600)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: occupato ? null : _provaDemo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: lavanda,
                        backgroundColor: superficie,
                        side: BorderSide(color: lavanda.withValues(alpha: .5)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      icon: _demoInCorso
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.science_rounded),
                      label: Text(s.t('Prova senza server (demo)', 'Try without a server (demo)')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('Dati simulati del Parco Sempione: nulla viene inviato.', 'Simulated Parco Sempione data: nothing is sent.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: testoSecondario),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
