import '../ambiente/formato_ambiente.dart';
import '../ambiente/stato_ambiente.dart';
import '../modelli/ambiente.dart';
import '../ui.dart';

/// Nomi dei link proposti dall'assistente. Avvisi, segnalazioni e idee usano
/// il loro titolo (che la chat recupera se il server non lo manda); i grafici
/// dicono quale grandezza e quale stazione. Così due link della stessa
/// risposta non si confondono.
class NomiFonti {
  NomiFonti({this.ambiente});

  /// Per i nomi delle grandezze e delle stazioni.
  final StatoAmbiente? ambiente;

  /// Lunghezza massima di un nome sul chip.
  static const int maxNome = 38;

  static const Set<String> _conTitolo = {
    TipiFonte.avviso,
    TipiFonte.miaSegnalazione,
    TipiFonte.segnalazione,
    TipiFonte.idea,
  };

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
    final titolo = f.title?.trim();
    if (titolo != null && titolo.isNotEmpty && _conTitolo.contains(f.type)) return accorcia(titolo);
    final id = f.id;
    return switch (f.type) {
      TipiFonte.statoParco => s.t('Stato del parco', 'Park status'),
      TipiFonte.avviso => id == null ? s.t('Avvisi del parco', 'Park notices') : s.t('Avviso n. $id', 'Notice no. $id'),
      TipiFonte.miaSegnalazione =>
        id == null ? s.t('Le mie segnalazioni', 'My reports') : s.t('Tua segnalazione n. $id', 'Your report no. $id'),
      TipiFonte.segnalazione => id == null ? s.t('Segnalazioni', 'Reports') : s.t('Segnalazione n. $id', 'Report no. $id'),
      TipiFonte.idea => id == null ? s.t('Idee', 'Ideas') : s.t('Idea n. $id', 'Idea no. $id'),
      TipiFonte.ambiente => _nomeAmbiente(f, s),
      TipiFonte.categorie => s.t('Segnala un problema', 'Report a problem'),
      _ => null,
    };
  }

  /// Toglie gli spazi doppi e taglia i titoli lunghi con i puntini.
  static String accorcia(String t) {
    final pulito = t.trim().replaceAll(RegExp(r'\s+'), ' ');
    return pulito.length <= maxNome ? pulito : '${pulito.substring(0, maxNome - 1).trimRight()}…';
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

  /// «Temperatura» → «temperatura», ma «PM2.5» resta com'è.
  static String _minuscola(String t) {
    if (t.length < 2 || t[1].toLowerCase() != t[1]) return t;
    return t[0].toLowerCase() + t.substring(1);
  }
}
