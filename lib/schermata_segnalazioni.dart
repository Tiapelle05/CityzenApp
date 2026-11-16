import 'dart:async';

import 'package:flutter/material.dart';

import 'citizen_api.dart';
import 'mappa_parco.dart';
import 'ui.dart';

/// Segnalazioni del parco: tutte (feed pubblico) e le proprie.
/// Si aggiorna in tempo reale dal WebSocket /citizen/ws.
class SchermataSegnalazioni extends StatefulWidget {
  final Copie s;
  const SchermataSegnalazioni({super.key, required this.s});

  @override
  State<SchermataSegnalazioni> createState() => _SchermataSegnalazioniState();
}

class _SchermataSegnalazioniState extends State<SchermataSegnalazioni> {
  bool _soloMie = false;
  /// La mappa è la vista iniziale: si capisce subito cosa succede e dove.
  bool _mappa = true;

  /// Segnalazione scelta sulla mappa (per id).
  Object? _selezionata;
  final GlobalKey _chiaveDettaglioMappa = GlobalKey();

  void _seleziona(Object? id) {
    setState(() => _selezionata = id);
    // La scheda sta sotto la mappa: la si porta in vista.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chiaveDettaglioMappa.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: durata(context, 350),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }
  bool _caricamento = true;
  String? _errore;
  List<Map<String, dynamic>> _items = [];
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
        _debounce = Timer(const Duration(milliseconds: 400), () => _carica(silenzioso: true));
      }
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _carica({bool silenzioso = false}) async {
    if (!silenzioso && mounted) {
      setState(() {
        _caricamento = true;
        _errore = null;
      });
    }
    try {
      final data = _soloMie
          ? await CitizenApi.instance.getMyReports(limit: 50)
          // Le idee (suggestion) hanno la loro schermata: qui solo i problemi
          : await CitizenApi.instance.getFeed(kind: 'problem', limit: 50);
      var rows = (data['items'] as List).cast<Map<String, dynamic>>();
      if (_soloMie) rows = await _conPosizione(rows);
      if (mounted) {
        setState(() {
          _items = rows;
          _caricamento = false;
          _errore = null;
          if (!rows.any((r) => r['id'] == _selezionata)) {
            _selezionata = null;
          }
        });
      }
    } catch (e) {
      final notFound = e is ApiException && e.statusCode == 404;
      if (mounted) {
        setState(() {
          _caricamento = false;
          _errore = notFound
              ? widget.s.t('Elenco non ancora disponibile sul server.', 'List not available on the server yet.')
              : e.toString();
        });
      }
    }
  }

  /// Il server reale mette la posizione solo nel dettaglio della segnalazione:
  /// per le proprie la si recupera da lì, così compaiono sulla mappa.
  /// (Quella delle segnalazioni altrui non viene mai inviata, per privacy.)
  Future<List<Map<String, dynamic>>> _conPosizione(List<Map<String, dynamic>> rows) {
    return Future.wait(rows.map((r) async {
      if (MappaParco.puntoDi(r) != null || r['id'] is! int) return r;
      try {
        final d = await CitizenApi.instance.getReport(r['id'] as int);
        return {...r, ...d};
      } catch (_) {
        return r;
      }
    }));
  }

  Color _coloreStato(String? st) => coloreStatoSegnalazione(st);

  Widget _scheda(Map<String, dynamic> r) {
    final s = widget.s;
    final testoDescr = (r['description'] ?? r['summary'] ?? '').toString();
    final foto = CitizenApi.instance.absoluteUrl(r['photo_url'] as String?);
    final mia = r['is_mine'] == true || _soloMie;
    final categoria = (r['category_label'] ?? r['category'] ?? '').toString();
    final codice = (r['code'] ?? '').toString();
    final rating = r['rating'];
    final statoLabel = r['status_label']?.toString() ?? '';
    final coloreStato = _coloreStato(r['status'] as String?);

    return Scheda(
      padding: EdgeInsets.zero,
      onTap: mia ? () => _dettaglio(r) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (foto != null)
            Image.network(
              foto,
              height: 170,
              width: double.infinity,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, sincrono) =>
                  sincrono ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: durata(context, 300), child: child),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoria.isNotEmpty ? categoria : codice,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: testo, height: 1.25),
                          ),
                          if (categoria.isNotEmpty && codice.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              codice,
                              style: const TextStyle(fontSize: 12.5, color: testoTenue, fontWeight: FontWeight.w600, letterSpacing: .3),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (statoLabel.isNotEmpty) ...[const SizedBox(width: 8), Etichetta(statoLabel, colore: coloreStato, puntino: true)],
                  ],
                ),
                if (testoDescr.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(testoDescr, style: const TextStyle(fontSize: 14.5, color: testo, height: 1.45)),
                ],
                if (rating is int && rating > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: List.generate(rating, (_) => const Icon(Icons.star_rounded, size: 18, color: sole))),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 15, color: testoTenue),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        formattaData(r['created_at'], ora: true),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: testoSecondario),
                      ),
                    ),
                    if (r['is_mine'] == true && !_soloMie)
                      Flexible(child: Etichetta(s.t('La tua segnalazione', 'Your report'), icona: Icons.person_rounded)),
                    if (mia) ...[const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, color: testoTenue)],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dettaglio(Map<String, dynamic> r) async {
    final s = widget.s;
    Map<String, dynamic> d = r;
    try {
      d = await CitizenApi.instance.getReport(r['id'] as int);
    } catch (_) {}
    if (!mounted) return;
    final storico = (d['history'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconaTonda(Icons.receipt_long_rounded, colore: cieloScuro, sfondo: cieloChiaro, dimensione: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['code']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Etichetta('${d['status_label']}', colore: _coloreStato(d['status'] as String?), puntino: true),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(s.t('Storico', 'History'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              for (final (i, h) in storico.indexed)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Column(
                          children: [
                            const SizedBox(height: 3),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == storico.length - 1 ? foresta : superficie,
                                border: Border.all(color: foresta, width: 2),
                              ),
                            ),
                            if (i < storico.length - 1) Expanded(child: Container(width: 2, color: bordo)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${h['status']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text(formattaData(h['at'], ora: true), style: const TextStyle(fontSize: 12.5, color: testoSecondario)),
                              if (h['note'] != null) ...[
                                const SizedBox(height: 4),
                                Text('${h['note']}', style: const TextStyle(fontSize: 14, height: 1.4)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vistaMappa(Copie s) {
    final conPosizione = [
      for (final r in _items)
        if (MappaParco.puntoDi(r) case final punto?) (r, punto),
    ];
    final senzaPosizione = _items.length - conPosizione.length;
    final scelta = _items.where((r) => r['id'] == _selezionata).firstOrNull;
    // La scelta si disegna per ultima, sopra le altre.
    final ordinate = [...conPosizione]..sort((a, b) => (a.$1['id'] == _selezionata ? 1 : 0) - (b.$1['id'] == _selezionata ? 1 : 0));

    return Column(
      key: ValueKey('mappa-$_soloMie'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MappaParco(
          altezza: 440,
          centro: MappaParco.centroParco(conPosizione.map((e) => e.$2)),
          onTocco: (_) => setState(() => _selezionata = null),
          marcatori: [
            for (final (r, punto) in ordinate)
              Marker(
                point: punto,
                width: Segnaposto.dimensione,
                height: Segnaposto.dimensione,
                child: Semantics(
                  button: true,
                  label: '${r['category_label'] ?? r['code']}, ${r['status_label'] ?? ''}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _seleziona(r['id']),
                    child: Segnaposto(
                      icona: iconaCategoria(r['category'] as String?),
                      colore: _coloreStato(r['status'] as String?),
                      selezionato: r['id'] == _selezionata,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (stato, it, en) in const [
              ('received', 'Ricevuta', 'Received'),
              ('in_progress', 'In lavorazione', 'In progress'),
              ('resolved', 'Risolta', 'Resolved'),
              ('closed', 'Chiusa', 'Closed'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _coloreStato(stato), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.t(it, en),
                    style: const TextStyle(fontSize: 12.5, color: testoSecondario, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          key: _chiaveDettaglioMappa,
          duration: durata(context, 220),
          child: scelta != null
              ? KeyedSubtree(key: ValueKey(scelta['id']), child: _scheda(scelta))
              : Riquadro(
                  key: const ValueKey('suggerimento'),
                  icona: conPosizione.isEmpty ? Icons.location_off_rounded : Icons.touch_app_rounded,
                  accento: Accento.blu,
                  messaggio: conPosizione.isEmpty
                      ? (_soloMie
                          ? s.t('Non hai ancora inviato segnalazioni. Usa «Segnala» qui sotto per farlo.',
                              'You have not sent any reports yet. Use “Report” below.')
                          : _items.isNotEmpty
                              ? s.t(
                                  'Per privacy il server non mostra dove si trovano le segnalazioni degli altri '
                                      '(${_items.length} nell’elenco). Scegli «Solo le mie» per vedere le tue sulla mappa.',
                                  'For privacy the server does not show where other people’s reports are '
                                      '(${_items.length} in the list). Choose “Only mine” to see yours on the map.',
                                )
                              : s.t('Nessuna segnalazione da mostrare sulla mappa.', 'No reports to show on the map.'))
                      : [
                          s.t('Tocca un puntino sulla mappa per vedere di cosa si tratta.', 'Tap a dot on the map to see what it is about.'),
                          if (senzaPosizione > 0)
                            s.t(
                              '$senzaPosizione senza posizione non sono sulla mappa.',
                              '$senzaPosizione without a location are not on the map.',
                            ),
                        ].join(' '),
                ),
        ),
      ],
    );
  }

  Widget _contenuto(Copie s) {
    if (_caricamento) {
      return CaricamentoScheletro(key: const ValueKey('caricamento'), etichetta: s.t('Caricamento delle segnalazioni', 'Loading reports'));
    }
    if (_errore != null) {
      return StatoVuoto(
        key: const ValueKey('errore'),
        icona: Icons.cloud_off_rounded,
        messaggio: _errore!,
        accento: Accento.arancio,
        onAzione: _carica,
        etichettaAzione: s.t('Riprova', 'Retry'),
      );
    }
    if (_mappa) return _vistaMappa(s);
    if (_items.isEmpty) {
      return StatoVuoto(
        key: ValueKey('vuoto-$_soloMie'),
        icona: Icons.inbox_outlined,
        messaggio: s.t('Nessuna segnalazione.', 'No reports.'),
        accento: Accento.blu,
      );
    }
    return Column(
      key: ValueKey('elenco-$_soloMie'),
      children: [
        for (final (i, r) in _items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Appare(indice: i, child: _scheda(r)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return RefreshIndicator(
      onRefresh: () => _carica(silenzioso: true),
      child: ContenitorePagina(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitoloPagina(
              titolo: s.t('Mappa delle segnalazioni', 'Reports map'),
              descrizione: s.t(
                'Ogni puntino è un problema segnalato; il colore dice a che punto è.',
                'Each dot is a reported problem; its colour shows its progress.',
              ),
              icona: Icons.map_rounded,
              accento: Accento.blu,
            ),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, icon: const Icon(Icons.map_outlined), label: Text(s.t('Mappa', 'Map'))),
                  ButtonSegment(value: false, icon: const Icon(Icons.view_agenda_outlined), label: Text(s.t('Elenco', 'List'))),
                ],
                selected: {_mappa},
                onSelectionChanged: (v) => setState(() {
                  _mappa = v.first;
                  _selezionata = null;
                }),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, icon: const Icon(Icons.groups_outlined), label: Text(s.t('Tutte', 'All'))),
                  ButtonSegment(value: true, icon: const Icon(Icons.person_outline_rounded), label: Text(s.t('Solo le mie', 'Only mine'))),
                ],
                selected: {_soloMie},
                onSelectionChanged: (v) {
                  setState(() => _soloMie = v.first);
                  unawaited(_carica());
                },
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(duration: durata(context, 250), child: _contenuto(s)),
          ],
        ),
      ),
    );
  }
}
