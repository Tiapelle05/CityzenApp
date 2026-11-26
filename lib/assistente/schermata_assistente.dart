import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../ambiente/stato_ambiente.dart';
import '../api/treeyes_api.dart';
import '../citizen_api.dart';
import '../modelli/ambiente.dart';
import '../ui.dart';
import 'nomi_fonti.dart';

/// Nome dell'assistente del parco, mostrato nella barra in basso, nella Home e nella chat.
const String nomeAssistente = 'Parky';

/// Testo mostrato in alto finché non arriva il `disclaimer` della prima risposta.
const String disclaimerPredefinito =
    'Risposte generate automaticamente dai dati dell’app. Valori stimati da sensori a basso costo, non certificati.';

/// Un messaggio della conversazione (solo in memoria).
class _Messaggio {
  final String ruolo;
  final String testo;
  final List<AssistantSource> fonti;

  /// Errore della domanda (solo per i messaggi dell'utente non andati a buon fine).
  String? errore;

  /// Vero se l'errore consente di riprovare.
  bool riprovabile;

  /// Vero dopo l'animazione di comparsa: scorrendo l'elenco non si ripete.
  bool mostrato = false;

  _Messaggio(this.ruolo, this.testo, {this.fonti = const []}) : riprovabile = false;

  bool get utente => ruolo == ChatTurn.utente;
}

/// "Chiedi al parco": domande all'assistente su stato del parco, avvisi,
/// segnalazioni, categorie e dati ambientali. La conversazione resta solo
/// in memoria e si perde chiudendo la schermata.
class SchermataAssistente extends StatefulWidget {
  final Copie s;

  /// Tocco su una fonte della risposta: porta alla schermata giusta.
  final void Function(BuildContext context, AssistantSource fonte)? onFonte;

  /// Vero quando la chat è una scheda della barra in basso: niente AppBar propria.
  final bool incorporata;

  /// Dati ambientali, per dare ai link dei grafici il nome della grandezza e della stazione.
  final StatoAmbiente? ambiente;

  const SchermataAssistente({super.key, required this.s, this.onFonte, this.incorporata = false, this.ambiente});

  @override
  State<SchermataAssistente> createState() => _SchermataAssistenteState();
}

class _SchermataAssistenteState extends State<SchermataAssistente> {
  final List<_Messaggio> _messaggi = [];
  final TextEditingController _campo = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _inAttesa = false;
  String? _disclaimer;
  late final NomiFonti _nomi = NomiFonti(ambiente: widget.ambiente);

  static const List<(String, String)> _suggerite = [
    ('Com’è l’aria adesso?', 'How is the air right now?'),
    ('Ci sono avvisi?', 'Are there any notices?'),
    ('A che punto è la mia segnalazione?', 'What is the status of my report?'),
    ('Che temperatura massima c’è stata ieri?', 'What was the highest temperature yesterday?'),
  ];

  @override
  void dispose() {
    _campo.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Cronologia da inviare: solo gli scambi riusciti, senza la domanda corrente.
  List<ChatTurn> _cronologiaPrima(_Messaggio domanda) {
    final turni = <ChatTurn>[];
    for (final m in _messaggi) {
      if (identical(m, domanda)) break;
      if (m.errore != null) continue;
      turni.add(ChatTurn(m.ruolo, m.testo));
    }
    return LimitiAssistente.cronologia(turni);
  }

  Future<void> _invia([String? testo]) async {
    final domanda = (testo ?? _campo.text).trim();
    if (domanda.isEmpty || domanda.length > LimitiAssistente.lunghezzaDomanda || _inAttesa) return;
    final msg = _Messaggio(ChatTurn.utente, domanda);
    setState(() => _messaggi.add(msg));
    _campo.clear();
    await _chiedi(msg);
  }

  Future<void> _riprova(_Messaggio msg) async {
    if (_inAttesa) return;
    setState(() {
      msg.errore = null;
      msg.riprovabile = false;
    });
    await _chiedi(msg);
  }

  Future<void> _chiedi(_Messaggio domanda) async {
    final s = widget.s;
    setState(() => _inAttesa = true);
    _scorriInFondo();
    try {
      final api = CitizenApi.instance;
      final risposta = await api.treeyes.askAssistant(await api.parcoInUso(), domanda.testo, _cronologiaPrima(domanda));
      // I nomi dei link arrivano prima della risposta, così non cambiano sotto gli occhi.
      await _nomi.prepara(risposta.sources).timeout(const Duration(seconds: 3), onTimeout: () {});
      if (!mounted) return;
      setState(() {
        _disclaimer ??= risposta.disclaimer.isEmpty ? null : risposta.disclaimer;
        final indice = _messaggi.indexOf(domanda);
        _messaggi.insert(indice + 1, _Messaggio(ChatTurn.assistente, risposta.answer, fonti: risposta.sources));
      });
      SemanticsService.sendAnnouncement(View.of(context), risposta.answer, Directionality.of(context));
    } catch (e) {
      if (!mounted) return;
      final (testo, riprovabile) = _messaggioErrore(e, s);
      setState(() {
        domanda.errore = testo;
        domanda.riprovabile = riprovabile;
      });
    } finally {
      if (mounted) setState(() => _inAttesa = false);
      _scorriInFondo();
    }
  }

  (String, bool) _messaggioErrore(Object e, Copie s) {
    if (e is ApiException) {
      switch (e.statusCode) {
        case 429:
          final minuti = e.retryAfter == null ? null : (e.retryAfter! / 60).ceil();
          return (
            minuti == null
                ? s.t('Hai fatto molte domande, riprova più tardi.', 'You asked many questions, try again later.')
                : s.t(
                    'Hai fatto molte domande, riprova tra $minuti min.',
                    'You asked many questions, try again in $minuti min.',
                  ),
            false,
          );
        case 503:
          return (s.t('L’assistente è occupato, riprova tra poco.', 'The assistant is busy, try again shortly.'), true);
        case 422:
          return (s.t('La domanda è vuota o troppo lunga.', 'The question is empty or too long.'), false);
      }
    }
    return (CitizenApi.instance.descriviErrore(e), true);
  }

  void _scorriInFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // Durante la dissolvenza tra due conversazioni gli elenchi agganciati
      // possono essere due: si scorre l'ultimo, quello che sta entrando.
      final posizione = _scroll.positions.last;
      final fine = posizione.maxScrollExtent;
      if (MediaQuery.of(context).disableAnimations) {
        posizione.jumpTo(fine);
      } else {
        posizione.animateTo(fine, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      }
    });
  }

  /// Ricomincia da capo: la conversazione resta solo in memoria.
  void _nuovaConversazione() {
    if (_inAttesa) return;
    setState(() {
      _messaggi.clear();
      _campo.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final corpo = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            if (widget.incorporata) _intestazione(),
            Expanded(
              child: AnimatedSwitcher(
                duration: durata(context, 260),
                switchInCurve: curvaEntrata,
                switchOutCurve: curvaUscita,
                transitionBuilder: transizioneMorbida,
                child: _messaggi.isEmpty
                    ? KeyedSubtree(key: const ValueKey('vuota'), child: _vuota())
                    : KeyedSubtree(key: const ValueKey('conversazione'), child: _conversazione()),
              ),
            ),
            _barraInvio(),
          ],
        ),
      ),
    );
    if (widget.incorporata) return corpo;
    return Scaffold(
      appBar: AppBar(
        title: const Text(nomeAssistente, style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [if (_messaggi.isNotEmpty) _pulsanteNuova(s)],
      ),
      body: SafeArea(top: false, child: corpo),
    );
  }

  Widget _pulsanteNuova(Copie s) => IconButton(
    tooltip: s.t('Nuova conversazione', 'New conversation'),
    onPressed: _inAttesa ? null : _nuovaConversazione,
    icon: const Icon(Icons.add_comment_outlined),
  );

  /// Intestazione della scheda: chi è l'assistente e, a conversazione iniziata,
  /// il pulsante per ricominciare.
  Widget _intestazione() {
    final s = widget.s;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: margineLaterale),
      child: TitoloPagina(
        titolo: nomeAssistente,
        descrizione: s.t('L’assistente del parco', 'Your park assistant'),
        icona: Icons.park_rounded,
        accento: Accento.viola,
        azione: AnimatedSwitcher(
          duration: durata(context, 200),
          child: _messaggi.isEmpty ? const SizedBox(key: ValueKey('vuoto')) : _pulsanteNuova(s),
        ),
      ),
    );
  }

  /// Avvertenze in piccolo sotto il campo: prima occupavano mezzo schermo in alto.
  Widget _avvertenze() {
    final s = widget.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Text(
        _disclaimer == null
            ? s.t(
                'Risposte automatiche dai dati dell’app. Non scrivere dati personali.',
                'Automatic answers from the app’s data. Do not write personal data.',
              )
            : '$_disclaimer ${s.t('Non scrivere dati personali.', 'Do not write personal data.')}',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, height: 1.3, color: testoSecondario),
      ),
    );
  }

  Widget _vuota() {
    final s = widget.s;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Center(
          child: IconaTonda(Icons.park_rounded, colore: lavanda, sfondo: lavandaChiaro, dimensione: 64),
        ),
        const SizedBox(height: 14),
        Text(
          s.t('Ciao, sono $nomeAssistente', 'Hi, I’m $nomeAssistente'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: testo),
        ),
        const SizedBox(height: 4),
        Text(
          s.t(
            'Chiedimi dello stato del parco, degli avvisi, delle tue segnalazioni e dell’aria.',
            'Ask me about the park status, notices, your reports and the air.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: testoSecondario),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (it, en) in _suggerite)
              ActionChip(
                avatar: Icon(Icons.chat_bubble_outline_rounded, size: 17, color: cieloScuro),
                label: Text(s.t(it, en)),
                onPressed: _inAttesa ? null : () => _invia(s.t(it, en)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _conversazione() {
    // Copia dei messaggi: dopo «nuova conversazione» l'elenco che sta svanendo
    // non deve leggere la lista ormai vuota (errore di indice se si ridisegna).
    final messaggi = List.of(_messaggi);
    final inAttesa = _inAttesa;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: messaggi.length + (inAttesa ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messaggi.length) return Appare(key: const ValueKey('scrive'), child: _staScrivendo());
        final m = messaggi[i];
        // Ogni messaggio compare una volta sola, con una breve dissolvenza.
        final nuovo = !m.mostrato;
        m.mostrato = true;
        return Appare(
          key: ObjectKey(m),
          attiva: nuovo,
          child: m.utente ? _bollaUtente(m) : _bollaAssistente(m),
        );
      },
    );
  }

  Widget _bollaUtente(_Messaggio m) {
    final s = widget.s;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: lavanda,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Semantics(
                  label: s.t('Tu: ${m.testo}', 'You: ${m.testo}'),
                  excludeSemantics: true,
                  child: Text(m.testo, style: TextStyle(fontSize: 15, height: 1.35, color: suAccento)),
                ),
              ),
              if (m.errore != null) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: coralloScuro),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          m.errore!,
                          style: TextStyle(fontSize: 13, color: coralloScuro, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (m.riprovabile)
                  TextButton.icon(
                    onPressed: _inAttesa ? null : () => _riprova(m),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(s.t('Riprova', 'Retry')),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bollaAssistente(_Messaggio m) {
    final s = widget.s;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(right: 32, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: IconaTonda(Icons.park_rounded, colore: lavanda, sfondo: lavandaChiaro, dimensione: 32),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: superficie,
                        border: Border.all(color: bordo),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                      child: SelectableText(m.testo, style: TextStyle(fontSize: 15, height: 1.4, color: testo)),
                    ),
                    if (m.fonti.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (f, etichetta) in _nomi.etichette(m.fonti, s))
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(_iconaFonte(f.type), size: 16, color: lavanda),
                                label: Text(etichetta, style: const TextStyle(fontSize: 12.5)),
                                tooltip: s.t('Apri: $etichetta', 'Open: $etichetta'),
                                onPressed: widget.onFonte == null ? null : () => widget.onFonte!(context, f),
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staScrivendo() {
    final s = widget.s;
    return Semantics(
      liveRegion: true,
      label: s.t('$nomeAssistente sta scrivendo', '$nomeAssistente is typing'),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            IconaTonda(Icons.park_rounded, colore: lavanda, sfondo: lavandaChiaro, dimensione: 32),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: superficie,
                border: Border.all(color: bordo),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PuntiniScrittura(),
                  const SizedBox(width: 10),
                  Text(
                    s.t('sta scrivendo…', 'typing…'),
                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: testoSecondario),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _puoInviare {
    final testo = _campo.text.trim();
    return !_inAttesa && testo.isNotEmpty && testo.length <= LimitiAssistente.lunghezzaDomanda;
  }

  Widget _barraInvio() {
    final s = widget.s;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: superficie,
        border: Border(top: BorderSide(color: bordo)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _campo,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: LimitiAssistente.lunghezzaDomanda,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  // _invia controlla da sé che la domanda sia valida.
                  onSubmitted: (_) => _invia(),
                  decoration: InputDecoration(hintText: s.t('Scrivi una domanda…', 'Ask a question…')),
                  // Il contatore compare solo vicino al limite.
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      maxLength != null && currentLength > maxLength - 100 ? Text('$currentLength/$maxLength') : null,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                // Solo il pulsante ascolta il campo: scrivendo non si ricostruisce
                // tutta la conversazione a ogni lettera.
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _campo,
                  builder: (context, _, _) {
                    final attivo = _puoInviare;
                    return AnimatedScale(
                      scale: attivo || _inAttesa ? 1 : .9,
                      duration: durata(context, 160),
                      curve: Curves.easeOutBack,
                      child: IconButton.filled(
                        tooltip: s.t('Invia', 'Send'),
                        style: IconButton.styleFrom(minimumSize: const Size(52, 52), backgroundColor: lavanda),
                        onPressed: attivo ? _invia : null,
                        icon: AnimatedSwitcher(
                          duration: durata(context, 180),
                          transitionBuilder: (figlio, a) => ScaleTransition(scale: a, child: figlio),
                          child: _inAttesa
                              ? SizedBox(
                                  key: ValueKey('attesa'),
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: suAccento),
                                )
                              : const Icon(Icons.send_rounded, key: ValueKey('invia')),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          _avvertenze(),
        ],
      ),
    );
  }

  static IconData _iconaFonte(String tipo) => switch (tipo) {
    TipiFonte.statoParco => Icons.home_rounded,
    TipiFonte.avviso => Icons.notifications_rounded,
    TipiFonte.miaSegnalazione => Icons.receipt_long_rounded,
    TipiFonte.segnalazione => Icons.place_rounded,
    TipiFonte.ambiente => Icons.air_rounded,
    TipiFonte.categorie => Icons.add_location_alt_rounded,
    _ => Icons.link_rounded,
  };
}

/// Tre puntini che si alzano a turno mentre l'assistente prepara la risposta.
/// Con le animazioni disattivate restano fermi.
class _PuntiniScrittura extends StatefulWidget {
  const _PuntiniScrittura();

  @override
  State<_PuntiniScrittura> createState() => _PuntiniScritturaState();
}

class _PuntiniScritturaState extends State<_PuntiniScrittura> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Ogni puntino si alza in un terzo diverso del ciclo e poi riscende.
  /// Create una volta sola: una ricostruzione (per esempio quando si apre la
  /// tastiera) non aggiunge altri ascoltatori al controller.
  late final List<Animation<double>> _salite = [
    for (var i = 0; i < 3; i++)
      _anim.drive(CurveTween(curve: Interval(i * .18, i * .18 + .45, curve: const _AndataRitorno(Curves.easeInOut)))),
  ];

  Widget _puntino(int i) {
    final salita = _salite[i];
    return AnimatedBuilder(
      animation: salita,
      builder: (context, figlio) => Transform.translate(
        offset: Offset(0, -4 * salita.value),
        child: Opacity(opacity: .45 + .55 * salita.value, child: figlio),
      ),
      child: Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: lavanda, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 3; i++) _puntino(i)]),
      );
}

/// Sale da 0 a 1 nella prima metà dell'intervallo e torna a 0 nella seconda.
class _AndataRitorno extends Curve {
  final Curve curva;
  const _AndataRitorno(this.curva);

  @override
  double transformInternal(double t) => curva.transform(t < .5 ? t * 2 : (1 - t) * 2);
}
