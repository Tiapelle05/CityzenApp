import 'dart:async';

import 'package:flutter/material.dart';

import '../api/mock_treeyes_api.dart';
import '../citizen_api.dart';
import '../modelli/ambiente.dart';
import '../ui.dart';
import 'formato_ambiente.dart';
import 'grafici_ambiente.dart';
import 'stato_ambiente.dart';

/// Apre la schermata Ambiente (eventualmente su una stazione).
Future<void> apriAmbiente(BuildContext context, StatoAmbiente stato, Copie s, {int? stazione}) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (_) => SchermataAmbiente(stato: stato, s: s, stazioneIniziale: stazione),
      ),
    );

/// Apre direttamente il grafico di una metrica.
Future<void> apriGrafico(
  BuildContext context,
  StatoAmbiente stato,
  Copie s, {
  required String metrica,
  int? stazione,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SchermataGrafico(stato: stato, s: s, metrica: metrica, stazione: stazione),
  ),
);

/// Valori e mini-curve di tutte le metriche di una stazione del parco.
class SchermataAmbiente extends StatefulWidget {
  final StatoAmbiente stato;
  final Copie s;
  final int? stazioneIniziale;

  /// Vero quando la schermata è la scheda «Aria» della barra in basso: niente AppBar propria.
  final bool incorporata;

  const SchermataAmbiente({
    super.key,
    required this.stato,
    required this.s,
    this.stazioneIniziale,
    this.incorporata = false,
  });

  @override
  State<SchermataAmbiente> createState() => _SchermataAmbienteState();
}

class _SchermataAmbienteState extends State<SchermataAmbiente> {
  late int? _stazione = widget.stazioneIniziale;

  @override
  void initState() {
    super.initState();
    if (widget.stato.ambiente == null) unawaited(widget.stato.ricarica());
  }

  Future<void> _cambiaScenario(String scenario) async {
    MockTreeyesApi.scenario = scenario;
    await widget.stato.ricarica();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final contenuto = ListenableBuilder(
      listenable: widget.stato,
      builder: (context, _) => RefreshIndicator(onRefresh: widget.stato.ricarica, child: _contenuto(context)),
    );
    if (widget.incorporata) {
      return Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: TitoloPagina(
                  titolo: s.t('Qualità dell’aria', 'Air quality'),
                  descrizione: s.t('Sensori del parco in tempo reale', 'Live park sensors'),
                  icona: Icons.air_rounded,
                  accento: Accento.verde,
                  azione: _menuScenario(s),
                ),
              ),
            ),
          ),
          Expanded(child: contenuto),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Qualità dell’aria', 'Air quality'), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [?_menuScenario(s)],
      ),
      body: contenuto,
    );
  }

  /// Scelta dello scenario simulato, solo in demo.
  Widget? _menuScenario(Copie s) => !CitizenApi.instance.demoMode
      ? null
      : PopupMenuButton<String>(
              tooltip: s.t('Scenario demo', 'Demo scenario'),
              icon: const Icon(Icons.science_outlined),
              onSelected: _cambiaScenario,
              itemBuilder: (_) => [
                for (final sc in ScenariAmbiente.tutti)
                  CheckedPopupMenuItem(
                    value: sc,
                    checked: MockTreeyesApi.scenario == sc,
                    child: Text(switch (sc) {
                      ScenariAmbiente.polveriAlte => s.t('Polveri alte', 'High dust'),
                      ScenariAmbiente.spenta => s.t('Stazione spenta', 'Station offline'),
                      ScenariAmbiente.preriscaldamento => s.t('Gas in preriscaldamento', 'Gas sensor warming up'),
                      _ => s.t('Normale', 'Normal'),
                    }),
                  ),
              ],
            );

  Widget _contenuto(BuildContext context) {
    final s = widget.s;
    final stato = widget.stato;
    final a = stato.ambiente;
    final List<Widget> figli;
    if (a == null) {
      figli = [
        if (stato.errore != null)
          StatoVuoto(
            icona: Icons.cloud_off_rounded,
            messaggio: stato.errore!,
            accento: Accento.arancio,
            onAzione: stato.ricarica,
            etichettaAzione: s.t('Riprova', 'Retry'),
          )
        else
          CaricamentoScheletro(
            numero: 3,
            etichetta: s.t('Caricamento dei dati ambientali', 'Loading environmental data'),
          ),
      ];
    } else if (a.stations.isEmpty) {
      figli = [
        StatoVuoto(
          icona: Icons.sensors_off_rounded,
          messaggio: s.t(
            'Questo parco non ha ancora stazioni ambientali.',
            'This park has no environmental stations yet.',
          ),
        ),
      ];
    } else {
      final st = a.stazione(_stazione)!;
      final ordine = stato.metriche.isEmpty
          ? st.readings.map((r) => r.metric).toList()
          : stato.metriche.map((m) => m.metric).toList();
      figli = [
        if (a.stations.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final x in a.stations)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(x.name),
                      selected: x.id == st.id,
                      onSelected: (_) => setState(() => _stazione = x.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _intestazione(a, st),
        const SizedBox(height: 14),
        for (final nome in ordine)
          if (st.lettura(nome) case final r?) ...[
            _schedaMetrica(st, r, stato.metrica(nome)),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 6),
        Riquadro(icona: Icons.info_outline_rounded, messaggio: avvertenzaSensori(s), accento: accentoSpento),
      ];
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: figli),
          ),
        ),
      ],
    );
  }

  Widget _intestazione(ParkEnvironment a, EnvStation st) {
    final s = widget.s;
    final accento = st.fresh ? accentoLivello(a.airQuality.level) : accentoSpento;
    final statoStazione = !st.online
        ? s.t('Stazione spenta', 'Station offline')
        : !st.fresh
        ? s.t('Dati non aggiornati', 'Data not up to date')
        : s.t('In funzione', 'Online');
    return Scheda(
      colore: accento.tinta,
      coloreBordo: accento.base.withValues(alpha: .3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: IconaTonda(
                  st.fresh ? Icons.air_rounded : Icons.cloud_off_rounded,
                  colore: accento.forte,
                  sfondo: superficie,
                  dimensione: 48,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        testoAria(a.airQuality, s),
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: testo),
                      ),
                    ),
                    Text(
                      [st.name, if (st.zone != null && st.zone != st.name) st.zone!].join(' · '),
                      style: const TextStyle(fontSize: 13.5, color: testoSecondario),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Etichetta(
                statoStazione,
                colore: st.fresh ? foresta : testoSecondario,
                sfondo: superficie,
                icona: st.online ? Icons.sensors_rounded : Icons.sensors_off_rounded,
              ),
              Etichetta(
                s.t('Ultima lettura ${quandoLettura(st.lastSeen, s)}', 'Last reading ${quandoLettura(st.lastSeen, s)}'),
                colore: testoSecondario,
                sfondo: superficie,
                icona: Icons.schedule_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _schedaMetrica(EnvStation st, StationReading r, EnvMetric? m) {
    final s = widget.s;
    final etichetta = etichettaMetrica(r.metric, s, m);
    final conLivello = m?.levels != null || r.level != null;
    final accento = !st.fresh
        ? accentoSpento
        : conLivello
        ? accentoLivello(r.level)
        : Accento.verde;
    final decimali = m?.decimals ?? 1;
    final delta = r.delta1h;
    final nonDisponibile = r.value == null;
    final nota = nonDisponibile
        ? (r.metric == Metriche.gas
              ? s.t('Sensore in preriscaldamento', 'Sensor warming up')
              : s.t('Dato non disponibile', 'Data not available'))
        : null;
    final testoDelta = delta == null || delta == 0
        ? s.t('stabile nell’ultima ora', 'steady in the last hour')
        : s.t(
            '${delta > 0 ? '+' : '−'}${formattaNumero(delta.abs(), decimali, s)} nell’ultima ora',
            '${delta > 0 ? '+' : '−'}${formattaNumero(delta.abs(), decimali, s)} in the last hour',
          );
    final minMax = r.min24h == null || r.max24h == null
        ? null
        : s.t(
            'Min ${formattaValore(r.min24h, m, s)} · Max ${formattaValore(r.max24h, m, s)} in 24 h',
            'Min ${formattaValore(r.min24h, m, s)} · Max ${formattaValore(r.max24h, m, s)} in 24 h',
          );
    final livello = conLivello && !nonDisponibile ? testoLivello(r.level, r.text, s) : null;
    final spark = st.spark24h[r.metric] ?? const [];

    return Semantics(
      button: true,
      hint: s.t('Apre il grafico', 'Opens the chart'),
      label: [
        etichetta,
        formattaValore(r.value, m, s),
        ?nota,
        if (livello != null && livello.isNotEmpty) livello,
        if (!nonDisponibile) testoDelta,
        ?minMax,
      ].join(', '),
      excludeSemantics: true,
      child: Scheda(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        onTap: () => apriGrafico(context, widget.stato, s, metrica: r.metric, stazione: st.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconaTonda(iconaMetrica(r.metric), colore: accento.forte, sfondo: accento.tinta, dimensione: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    etichetta,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: testo),
                  ),
                ),
                if (livello != null && livello.isNotEmpty) BadgeLivello(livello: st.fresh ? r.level : null, testo: livello),
                const Icon(Icons.chevron_right_rounded, color: testoTenue),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            formattaValore(r.value, m, s, conUnita: false),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: st.fresh ? testo : testoSecondario,
                              letterSpacing: -.5,
                            ),
                          ),
                          if (!nonDisponibile) ...[
                            const SizedBox(width: 5),
                            Text(
                              unitaMostrata(m, s),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: testoSecondario),
                            ),
                          ],
                        ],
                      ),
                      if (nota != null)
                        Text(
                          nota,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: testoSecondario),
                        )
                      else
                        Row(
                          children: [
                            Icon(
                              delta == null || delta == 0
                                  ? Icons.trending_flat_rounded
                                  : delta > 0
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 16,
                              color: testoSecondario,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(testoDelta, style: const TextStyle(fontSize: 12.5, color: testoSecondario)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: MiniCurva(valori: spark, colore: accento.base),
                ),
              ],
            ),
            if (minMax != null) ...[
              const SizedBox(height: 8),
              Text(minMax, style: const TextStyle(fontSize: 12.5, color: testoSecondario)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Andamento di una metrica nelle ultime 24 ore, 7 o 30 giorni.
class SchermataGrafico extends StatefulWidget {
  final StatoAmbiente stato;
  final Copie s;
  final String metrica;
  final int? stazione;

  const SchermataGrafico({super.key, required this.stato, required this.s, required this.metrica, this.stazione});

  @override
  State<SchermataGrafico> createState() => _SchermataGraficoState();
}

class _SchermataGraficoState extends State<SchermataGrafico> {
  String _intervallo = Intervalli.giorno;
  EnvSeries? _serie;
  String? _errore;
  bool _caricamento = true;
  int _richiesta = 0;

  @override
  void initState() {
    super.initState();
    if (widget.stato.metriche.isEmpty) unawaited(widget.stato.ricarica(silenzioso: true));
    unawaited(_carica());
  }

  Future<void> _carica() async {
    final numero = ++_richiesta;
    setState(() {
      _caricamento = true;
      _errore = null;
    });
    try {
      final api = CitizenApi.instance;
      final serie = await api.treeyes.environmentSeries(
        await api.parcoInUso(),
        metric: widget.metrica,
        range: _intervallo,
        stationId: widget.stazione,
      );
      if (!mounted || numero != _richiesta) return;
      setState(() {
        _serie = serie;
        _caricamento = false;
      });
    } catch (e) {
      if (!mounted || numero != _richiesta) return;
      setState(() {
        _errore = CitizenApi.instance.descriviErrore(e);
        _caricamento = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListenableBuilder(
      listenable: widget.stato,
      builder: (context, _) {
        final m = widget.stato.metrica(widget.metrica);
        final etichetta = etichettaMetrica(widget.metrica, s, m);
        final stazione = widget.stato.ambiente?.stazione(widget.stazione);
        final lettura = stazione?.lettura(widget.metrica);
        final conLivello = m?.levels != null;
        final colore = conLivello ? accentoLivello(lettura?.level).base : foresta;
        return Scaffold(
          appBar: AppBar(
            title: Text(etichetta, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: RefreshIndicator(
            onRefresh: _carica,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (stazione != null)
                  Text(
                    '${stazione.name} · ${s.t('ora', 'now')} ${formattaValore(lettura?.value, m, s)}',
                    style: const TextStyle(fontSize: 14, color: testoSecondario, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: Intervalli.giorno, label: Text(s.t('24 h', '24 h'))),
                    ButtonSegment(value: Intervalli.settimana, label: Text(s.t('7 giorni', '7 days'))),
                    ButtonSegment(value: Intervalli.mese, label: Text(s.t('30 giorni', '30 days'))),
                  ],
                  selected: {_intervallo},
                  onSelectionChanged: (v) {
                    setState(() => _intervallo = v.first);
                    unawaited(_carica());
                  },
                ),
                const SizedBox(height: 16),
                Scheda(padding: const EdgeInsets.fromLTRB(8, 18, 16, 10), child: _grafico(m, colore)),
                const SizedBox(height: 12),
                if (_serie case final serie? when !_caricamento && _errore == null) _riepilogo(serie, m),
                const SizedBox(height: 12),
                Riquadro(
                  icona: Icons.info_outline_rounded,
                  accento: accentoSpento,
                  messaggio: [
                    s.t(
                      'La linea è la media; la fascia chiara va dal minimo al massimo. Le interruzioni sono periodi senza dati.',
                      'The line is the average; the light band spans minimum to maximum. Gaps are periods without data.',
                    ),
                    if (m?.senzaUnita ?? false)
                      s.t(
                        'Il gas è un indice senza unità: vale circa 1 in aria pulita.',
                        'Gas is a unitless index: about 1 in clean air.',
                      ),
                    avvertenzaSensori(s),
                  ].join('\n\n'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _grafico(EnvMetric? m, Color colore) {
    final s = widget.s;
    if (_caricamento) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Semantics(
            label: s.t('Caricamento del grafico', 'Loading chart'),
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (_errore != null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errore!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: testoSecondario),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _carica,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.t('Riprova', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }
    final serie = _serie!;
    return Semantics(
      label: s.t(
        'Grafico ${etichettaMetrica(widget.metrica, s, m)}',
        'Chart ${etichettaMetrica(widget.metrica, s, m)}',
      ),
      child: GraficoSerie(serie: serie, metrica: m, s: s, colore: colore),
    );
  }

  Widget _riepilogo(EnvSeries serie, EnvMetric? m) {
    final s = widget.s;
    final medie = serie.points.map((p) => p.avg).whereType<double>().toList();
    if (medie.isEmpty) return const SizedBox.shrink();
    final minimi = serie.points.map((p) => p.min ?? p.avg).whereType<double>();
    final massimi = serie.points.map((p) => p.max ?? p.avg).whereType<double>();
    final media = medie.reduce((a, b) => a + b) / medie.length;
    Widget voce(String titolo, double v) => Expanded(
      child: Column(
        children: [
          Text(
            formattaValore(v, m, s),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: testo),
          ),
          Text(titolo, style: const TextStyle(fontSize: 12, color: testoSecondario)),
        ],
      ),
    );
    return Scheda(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          voce(s.t('Minimo', 'Minimum'), minimi.reduce((a, b) => a < b ? a : b)),
          voce(s.t('Media', 'Average'), media),
          voce(s.t('Massimo', 'Maximum'), massimi.reduce((a, b) => a > b ? a : b)),
        ],
      ),
    );
  }
}
