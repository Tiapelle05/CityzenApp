import 'dart:async';

import 'package:flutter/material.dart';

import 'citizen_api.dart';
import 'main.dart';

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
    if (!silenzioso && mounted) setState(() { _caricamento = true; _errore = null; });
    try {
      final data = _soloMie
          ? await CitizenApi.instance.getMyReports(limit: 50)
          // Le idee (suggestion) hanno la loro schermata: qui solo i problemi
          : await CitizenApi.instance.getFeed(kind: 'problem', limit: 50);
      final rows = (data['items'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _items = rows; _caricamento = false; _errore = null; });
    } catch (e) {
      final notFound = e is ApiException && e.statusCode == 404;
      if (mounted) {
        setState(() {
          _caricamento = false;
          _errore = notFound
              ? widget.s.t('Elenco non ancora disponibile sul server.',
                  'List not available on the server yet.')
              : e.toString();
        });
      }
    }
  }

  Color _coloreStato(String? st) => switch (st) {
        'resolved' => verde,
        'in_progress' => const Color(0xFF8A5A00),
        'closed' => testoSecondario,
        _ => const Color(0xFF145A86),
      };

  String _data(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _scheda(Map<String, dynamic> r) {
    final s = widget.s;
    final testoDescr = (r['description'] ?? r['summary'] ?? '').toString();
    final foto = CitizenApi.instance.absoluteUrl(r['photo_url'] as String?);
    final mia = r['is_mine'] == true || _soloMie;
    final categoria = (r['category_label'] ?? r['category'] ?? '').toString();
    final rating = r['rating'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: mia ? () => _dettaglio(r) : null,
        child: Scheda(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [if (categoria.isNotEmpty) categoria, r['code']].join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: testo),
                    ),
                  ),
                  Chip(
                    label: Text(r['status_label']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: _coloreStato(r['status'] as String?),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(testoDescr, style: const TextStyle(color: testo, height: 1.4)),
              if (rating != null) ...[
                const SizedBox(height: 6),
                Text('★' * (rating as int), style: const TextStyle(color: Color(0xFF8A5A00))),
              ],
              if (foto != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(foto, height: 160, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(_data(r['created_at']),
                      style: const TextStyle(fontSize: 12, color: testoSecondario)),
                  const Spacer(),
                  if (r['is_mine'] == true && !_soloMie)
                    Text(s.t('La tua segnalazione', 'Your report'),
                        style: const TextStyle(fontSize: 12, color: verde, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
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
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d['code']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${d['status_label']}'),
            const SizedBox(height: 14),
            Text(s.t('Storico', 'History'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final h in storico)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${_data(h['at'])} · ${h['status']}${h['note'] != null ? ' — ${h['note']}' : ''}'),
              ),
          ],
        ),
      ),
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
              titolo: s.t('Segnalazioni', 'Reports'),
              descrizione: s.t('Cosa viene segnalato nel parco e a che punto è.',
                  'What is reported in the park and its progress.'),
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(s.t('Nel parco', 'In the park')),
                  selected: !_soloMie,
                  onSelected: (_) { setState(() => _soloMie = false); unawaited(_carica()); },
                ),
                ChoiceChip(
                  label: Text(s.t('Le mie', 'Mine')),
                  selected: _soloMie,
                  onSelected: (_) { setState(() => _soloMie = true); unawaited(_carica()); },
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_caricamento)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
            else if (_errore != null)
              Scheda(child: Text(_errore!))
            else if (_items.isEmpty)
              Scheda(child: Text(s.t('Nessuna segnalazione.', 'No reports.')))
            else
              ..._items.map(_scheda),
          ],
        ),
      ),
    );
  }
}
