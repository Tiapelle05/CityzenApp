import '../ambiente/formato_ambiente.dart';
import '../ambiente/stato_ambiente.dart';
import '../citizen_api.dart';
import '../modelli/ambiente.dart';
import '../ui.dart';

/// Nomi dei link proposti dall'assistente. Invece di «Avviso» o «Grafico»
/// dicono quale avviso, quale segnalazione, quale grandezza e quale stazione,
/// così due link della stessa risposta non si confondono.
class NomiFonti {
  NomiFonti({CitizenApi? api, this.ambiente}) : _api = api ?? CitizenApi.instance;

  final CitizenApi _api;

  /// Per i nomi delle grandezze e delle stazioni.
  final StatoAmbiente? ambiente;

  final Map<int, String> _avvisi = {};
  final Map<int, Map<String, dynamic>> _segnalazioni = {};

  static bool _diSegnalazione(AssistantSource f) =>
      f.type == TipiFonte.miaSegnalazione || f.type == TipiFonte.segnalazione;

  /// Carica i nomi che mancano: titoli degli avvisi e categorie delle segnalazioni.
  /// Se qualcosa non arriva resta un nome generico con il numero.
  Future<void> prepara(List<AssistantSource> fonti) async {
    final lavori = <Future<void>>[];
    if (fonti.any((f) => f.type == TipiFonte.avviso && f.id != null && !_avvisi.containsKey(f.id))) {
      lavori.add(_api.getNotices().then((elenco) {
        for (final a in elenco) {
          final id = (a['id'] as num?)?.toInt();
          final titolo = (a['title'] as String?)?.trim();
          if (id != null && titolo != null && titolo.isNotEmpty) _avvisi[id] = titolo;
        }
      }));
    }
    final daCaricare = {
      for (final f in fonti)
        if (_diSegnalazione(f) && f.id != null && !_segnalazioni.containsKey(f.id)) f.id!,
    };
    for (final id in daCaricare) {
      lavori.add(_api.getReport(id).then((r) {
        _segnalazioni[id] = r;
      }));
    }
    await Future.wait([for (final l in lavori) l.catchError((Object _) {})]);
  }

  /// Fonti da mostrare, senza doppioni, ciascuna con il suo nome.
  /// Restano fuori i tipi che l'app non sa aprire.
  List<(AssistantSource, String)> etichette(List<AssistantSource> fonti, Copie s) {
    final viste = <String>{};
    final risultato = <(AssistantSource, String)>[];
    for (final f in fonti) {
      if (!viste.add('${f.type}|${f.id}|${f.stationId}|${f.metric}')) continue;
      final nome = this.nome(f, s);
      if (nome != null) risultato.add((f, nome));
    }
    // Se due nomi restano uguali si aggiunge il numero, o la posizione.
    final conteggio = <String, int>{};
    for (final (_, n) in risultato) {
      conteggio[n] = (conteggio[n] ?? 0) + 1;
    }
    final usati = <String, int>{};
    return [
      for (final (f, n) in risultato)
        if (conteggio[n]! < 2)
          (f, n)
        else
          (f, '$n · ${f.id != null ? s.t('n. ${f.id}', 'no. ${f.id}') : '${usati[n] = (usati[n] ?? 0) + 1}'}'),
    ];
  }

  /// Nome di un link; null per i tipi che l'app non sa aprire.
  String? nome(AssistantSource f, Copie s) {
    final dalBackend = f.label?.trim();
    if (dalBackend != null && dalBackend.isNotEmpty) return dalBackend;
    return switch (f.type) {
      TipiFonte.statoParco => s.t('Stato del parco', 'Park status'),
      TipiFonte.avviso => _nomeAvviso(f, s),
      TipiFonte.miaSegnalazione || TipiFonte.segnalazione => _nomeSegnalazione(f, s),
      TipiFonte.ambiente => _nomeAmbiente(f, s),
      TipiFonte.categorie => s.t('Segnala un problema', 'Report a problem'),
      _ => null,
    };
  }

  String _nomeAvviso(AssistantSource f, Copie s) {
    final id = f.id;
    if (id == null) return s.t('Avvisi del parco', 'Park notices');
    return _avvisi[id] ?? s.t('Avviso n. $id', 'Notice no. $id');
  }

  String _nomeSegnalazione(AssistantSource f, Copie s) {
    final id = f.id;
    final mia = f.type == TipiFonte.miaSegnalazione;
    final r = id == null ? null : _segnalazioni[id];
    final categoria = (r?['category_label'] ?? r?['category'])?.toString().trim();
    if (categoria == null || categoria.isEmpty) {
      if (id == null) return mia ? s.t('Le mie segnalazioni', 'My reports') : s.t('Segnalazioni', 'Reports');
      return mia ? s.t('Tua segnalazione n. $id', 'Your report no. $id') : s.t('Segnalazione n. $id', 'Report no. $id');
    }
    final data = DateTime.tryParse(r?['created_at']?.toString() ?? '')?.toLocal();
    return data == null ? categoria : '$categoria · ${_due(data.day)}/${_due(data.month)}';
  }

  String _nomeAmbiente(AssistantSource f, Copie s) {
    final stazione = f.stationId == null
        ? null
        : ambiente?.ambiente?.stations.where((st) => st.id == f.stationId).firstOrNull?.name.trim();
    final nomeStazione = stazione == null || stazione.isEmpty
        ? (f.stationId == null ? null : s.t('Stazione ${f.stationId}', 'Station ${f.stationId}'))
        : stazione;
    final metrica = f.metric;
    if (metrica == null) return nomeStazione ?? s.t('Qualità dell’aria', 'Air quality');
    final grandezza = etichettaMetrica(metrica, s, ambiente?.metrica(metrica));
    final grafico = s.t('Grafico ${_minuscola(grandezza)}', '$grandezza chart');
    return nomeStazione == null ? grafico : '$grafico · $nomeStazione';
  }

  static String _due(int n) => n.toString().padLeft(2, '0');

  /// «Temperatura» → «temperatura», ma «PM2.5» resta com'è.
  static String _minuscola(String t) {
    if (t.length < 2 || t[1].toLowerCase() != t[1]) return t;
    return t[0].toLowerCase() + t.substring(1);
  }
}
