import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../api/treeyes_api.dart';
import '../citizen_api.dart';
import '../modelli/ambiente.dart';
import '../ui.dart';

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

  const SchermataAssistente({super.key, required this.s, this.onFonte, this.incorporata = false});

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

  static const List<(String, String)> _suggerite = [
    ('Com’è l’aria adesso?', 'How is the air right now?'),
    ('Ci sono avvisi?', 'Are there any notices?'),
    ('A che punto è la mia segnalazione?', 'What is the status of my report?'),
    ('Quali idee sono state proposte?', 'Which ideas have been suggested?'),
    ('Che temperatura massima c’è stata ieri?', 'What was the highest temperature yesterday?'),
  ];

  @override
  void initState() {
    super.initState();
    _campo.addListener(() => setState(() {}));
  }

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
      final fonti = await _conTitoli(risposta.sources);
      if (!mounted) return;
      setState(() {
        _disclaimer ??= risposta.disclaimer.isEmpty ? null : risposta.disclaimer;
        final indice = _messaggi.indexOf(domanda);
        _messaggi.insert(indice + 1, _Messaggio(ChatTurn.assistente, risposta.answer, fonti: fonti));
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

  /// Completa le fonti senza titolo (il backend manda solo tipo e id) leggendo
  /// avvisi e segnalazioni dall'app. Una segnalazione `suggestion` diventa un'idea.
  /// Se qualcosa non si carica il chip resta con l'etichetta generica.
  Future<List<AssistantSource>> _conTitoli(List<AssistantSource> fonti) async {
    final api = CitizenApi.instance;
    final senzaTitolo = fonti.where((f) => f.id != null && (f.title?.trim().isEmpty ?? true)).toList();
    if (senzaTitolo.isEmpty) return fonti;

    Map<int, String>? titoliAvvisi;
    if (senzaTitolo.any((f) => f.type == TipiFonte.avviso)) {
      try {
        titoliAvvisi = {
          for (final a in await api.getNotices())
            if (a['id'] is num && a['title'] is String) (a['id'] as num).toInt(): a['title'] as String,
        };
      } catch (_) {}
    }

    Future<AssistantSource> completa(AssistantSource f) async {
      if (f.id == null || (f.title?.trim().isNotEmpty ?? false)) return f;
      switch (f.type) {
        case TipiFonte.avviso:
          return f.conTitolo(titoliAvvisi?[f.id]);
        case TipiFonte.segnalazione || TipiFonte.miaSegnalazione || TipiFonte.idea:
          try {
            final r = await api.getReport(f.id!);
            final idea = r['kind'] == 'suggestion';
            return f.conTitolo(titoloSegnalazione(r), tipo: idea ? TipiFonte.idea : null);
          } catch (_) {
            return f;
          }
      }
      return f;
    }

    return Future.wait(fonti.map(completa)).timeout(const Duration(seconds: 6), onTimeout: () => fonti);
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
      if (!_scroll.hasClients) return;
      final fine = _scroll.position.maxScrollExtent;
      if (MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(fine);
      } else {
        _scroll.animateTo(fine, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
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
            _avvertenze(),
            Expanded(child: _messaggi.isEmpty ? _vuota() : _conversazione()),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: IconaTonda(Icons.park_rounded, colore: foresta, sfondo: menta, dimensione: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    nomeAssistente,
                    style: TextStyle(fontSize: 21, height: 1.15, fontWeight: FontWeight.w800, color: testo, letterSpacing: -.3),
                  ),
                  Text(
                    s.t('L’assistente del parco', 'Your park assistant'),
                    style: const TextStyle(fontSize: 13, color: testoSecondario),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: durata(context, 200),
            child: _messaggi.isEmpty ? const SizedBox(key: ValueKey('vuoto')) : _pulsanteNuova(s),
          ),
        ],
      ),
    );
  }

  Widget _avvertenze() {
    final s = widget.s;
    final disclaimer =
        _disclaimer ??
        s.t(
          disclaimerPredefinito,
          'Answers are generated automatically from the app’s data. Values estimated by low-cost, non-certified sensors.',
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cieloChiaro,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cielo.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: cieloScuro),
              const SizedBox(width: 8),
              Expanded(
                child: Text(disclaimer, style: const TextStyle(fontSize: 12.5, height: 1.35, color: testo)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.privacy_tip_outlined, size: 18, color: cieloScuro),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.t('Non scrivere dati personali nelle domande.', 'Do not write personal data in your questions.'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cieloScuro),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vuota() {
    final s = widget.s;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        const Center(
          child: IconaTonda(Icons.park_rounded, colore: foresta, sfondo: menta, dimensione: 64),
        ),
        const SizedBox(height: 14),
        Text(
          s.t('Ciao, sono $nomeAssistente', 'Hi, I’m $nomeAssistente'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: testo),
        ),
        const SizedBox(height: 4),
        Text(
          s.t(
            'Chiedimi dello stato del parco, degli avvisi, delle tue segnalazioni, delle idee e dell’aria.',
            'Ask me about the park status, notices, your reports, ideas and the air.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: testoSecondario),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (it, en) in _suggerite)
              ActionChip(
                avatar: const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: cieloScuro),
                label: Text(s.t(it, en)),
                onPressed: _inAttesa ? null : () => _invia(s.t(it, en)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _conversazione() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messaggi.length + (_inAttesa ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messaggi.length) return _staScrivendo();
        final m = _messaggi[i];
        return m.utente ? _bollaUtente(m) : _bollaAssistente(m);
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
                decoration: const BoxDecoration(
                  color: foresta,
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
                  child: Text(m.testo, style: const TextStyle(fontSize: 15, height: 1.35, color: Colors.white)),
                ),
              ),
              if (m.errore != null) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: coralloScuro),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          m.errore!,
                          style: const TextStyle(fontSize: 13, color: coralloScuro, fontWeight: FontWeight.w700),
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
              const ExcludeSemantics(
                child: IconaTonda(Icons.park_rounded, colore: foresta, sfondo: menta, dimensione: 32),
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
                      child: SelectableText(m.testo, style: const TextStyle(fontSize: 15, height: 1.4, color: testo)),
                    ),
                    if (m.fonti.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in m.fonti)
                            if (_etichettaFonte(f, s) case final etichetta?)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(_iconaFonte(f.type), size: 16, color: foresta),
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
            const IconaTonda(Icons.park_rounded, colore: foresta, sfondo: menta, dimensione: 32),
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
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(
                    s.t('sta scrivendo…', 'typing…'),
                    style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: testoSecondario),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraInvio() {
    final s = widget.s;
    final testo = _campo.text.trim();
    final puoInviare = !_inAttesa && testo.isNotEmpty && testo.length <= LimitiAssistente.lunghezzaDomanda;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: superficie,
        border: Border(top: BorderSide(color: bordo)),
      ),
      child: Row(
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
              onSubmitted: puoInviare ? (_) => _invia() : null,
              decoration: InputDecoration(
                hintText: s.t('Scrivi a $nomeAssistente…', 'Message $nomeAssistente…'),
                labelText: s.t('Domanda', 'Question'),
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: IconButton.filled(
              tooltip: s.t('Invia', 'Send'),
              style: IconButton.styleFrom(minimumSize: const Size(52, 52), backgroundColor: foresta),
              onPressed: puoInviare ? _invia : null,
              icon: _inAttesa
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconaFonte(String tipo) => switch (tipo) {
    TipiFonte.statoParco => Icons.home_rounded,
    TipiFonte.avviso => Icons.notifications_rounded,
    TipiFonte.miaSegnalazione => Icons.receipt_long_rounded,
    TipiFonte.segnalazione => Icons.place_rounded,
    TipiFonte.idea => Icons.lightbulb_rounded,
    TipiFonte.ambiente => Icons.air_rounded,
    TipiFonte.categorie => Icons.add_location_alt_rounded,
    _ => Icons.link_rounded,
  };

  /// Lunghezza massima del titolo sul chip.
  static const int _maxTitolo = 38;

  static String _accorcia(String t) {
    final pulito = t.trim().replaceAll(RegExp(r'\s+'), ' ');
    return pulito.length <= _maxTitolo ? pulito : '${pulito.substring(0, _maxTitolo - 1).trimRight()}…';
  }

  /// Etichetta del chip; null per i tipi che l'app non sa aprire.
  /// Avvisi, segnalazioni e idee mostrano il proprio titolo, così i link si distinguono.
  static String? _etichettaFonte(AssistantSource f, Copie s) {
    final titolo = f.title?.trim();
    if (titolo != null && titolo.isNotEmpty && _conTitolo.contains(f.type)) return _accorcia(titolo);
    return _etichettaGenerica(f, s);
  }

  static const Set<String> _conTitolo = {
    TipiFonte.avviso,
    TipiFonte.miaSegnalazione,
    TipiFonte.segnalazione,
    TipiFonte.idea,
  };

  static String? _etichettaGenerica(AssistantSource f, Copie s) => switch (f.type) {
    TipiFonte.statoParco => s.t('Stato del parco', 'Park status'),
    TipiFonte.avviso => f.id == null ? s.t('Avvisi', 'Notices') : s.t('Avviso n. ${f.id}', 'Notice #${f.id}'),
    TipiFonte.miaSegnalazione =>
      f.id == null ? s.t('Le tue segnalazioni', 'Your reports') : s.t('Tua segnalazione n. ${f.id}', 'Your report #${f.id}'),
    TipiFonte.segnalazione => f.id == null ? s.t('Segnalazioni', 'Reports') : s.t('Segnalazione n. ${f.id}', 'Report #${f.id}'),
    TipiFonte.idea => f.id == null ? s.t('Idee', 'Ideas') : s.t('Idea n. ${f.id}', 'Idea #${f.id}'),
    TipiFonte.ambiente => f.metric == null ? s.t('Dati ambientali', 'Environmental data') : s.t('Grafico', 'Chart'),
    TipiFonte.categorie => s.t('Segnala', 'Report'),
    _ => null,
  };
}
