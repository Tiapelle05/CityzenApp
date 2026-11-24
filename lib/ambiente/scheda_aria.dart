import 'package:flutter/material.dart';

import '../modelli/ambiente.dart';
import '../ui.dart';
import 'formato_ambiente.dart';
import 'stato_ambiente.dart';

/// Card "Aria nel parco" della Home: qualità dell'aria e due o tre valori
/// della prima stazione. Non compare se il parco non ha stazioni.
class SchedaAriaParco extends StatelessWidget {
  final StatoAmbiente stato;
  final Copie s;
  final VoidCallback onApri;

  /// Versione su una sola riga per la Home: giudizio sull'aria e temperatura.
  final bool compatta;

  const SchedaAriaParco({super.key, required this.stato, required this.s, required this.onApri, this.compatta = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stato,
      builder: (context, _) {
        final a = stato.ambiente;
        if (a == null || a.stations.isEmpty) return const SizedBox.shrink();
        final st = a.stations.first;
        final aggiornata = st.fresh;
        final accento = aggiornata ? accentoLivello(a.airQuality.level) : accentoSpento;
        final titolo = testoAria(a.airQuality, s);
        final sottotitolo = aggiornata
            ? s.t('Ultima lettura ${quandoLettura(st.lastSeen, s)}', 'Last reading ${quandoLettura(st.lastSeen, s)}')
            : s.t(
                'Dati non aggiornati, ultima lettura ${quandoLettura(st.lastSeen, s)}',
                'Data not up to date, last reading ${quandoLettura(st.lastSeen, s)}',
              );

        Widget valore(String metrica) {
          final r = st.lettura(metrica);
          final m = stato.metrica(metrica);
          if (r == null) return const SizedBox.shrink();
          return Expanded(
            child: Semantics(
              label:
                  '${etichettaMetrica(metrica, s, m)}: ${formattaValore(r.value, m, s)}'
                  '${r.text != null ? ', ${testoLivello(r.level, r.text, s)}' : ''}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(iconaMetrica(metrica), size: 20, color: aggiornata ? accento.forte : testoTenue),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattaValore(r.value, m, s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: aggiornata ? testo : testoSecondario,
                          ),
                        ),
                        Text(
                          etichettaMetrica(metrica, s, m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: testoSecondario),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (compatta) return _compatta(st, accento, titolo, sottotitolo, aggiornata);

        return Semantics(
          button: true,
          label: '${s.t('Aria nel parco', 'Air in the park')}: $titolo. $sottotitolo',
          child: Scheda(
            onTap: onApri,
            colore: accento.tinta,
            coloreBordo: accento.base.withValues(alpha: .3),
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: IconaTonda(
                        aggiornata ? Icons.air_rounded : Icons.cloud_off_rounded,
                        colore: accento.forte,
                        sfondo: superficie,
                        dimensione: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('ARIA NEL PARCO', 'AIR IN THE PARK'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: accento.forte,
                              letterSpacing: .8,
                            ),
                          ),
                          Text(
                            titolo,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: testo,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: accento.forte),
                  ],
                ),
                const SizedBox(height: 14),
                Row(children: [valore(Metriche.temperatura), valore(Metriche.polveri), valore(Metriche.umidita)]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      aggiornata ? Icons.schedule_rounded : Icons.warning_amber_rounded,
                      size: 15,
                      color: testoSecondario,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(sottotitolo, style: TextStyle(fontSize: 12.5, color: testoSecondario)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on SchedaAriaParco {
  Widget _compatta(EnvStation st, Accento accento, String titolo, String sottotitolo, bool aggiornata) {
    final temp = st.lettura(Metriche.temperatura);
    final mTemp = stato.metrica(Metriche.temperatura);
    return Semantics(
      button: true,
      label: '${s.t('Aria nel parco', 'Air in the park')}: $titolo. '
          '${temp == null ? '' : '${etichettaMetrica(Metriche.temperatura, s, mTemp)} ${formattaValore(temp.value, mTemp, s)}. '}'
          '$sottotitolo',
      excludeSemantics: true,
      child: Scheda(
        onTap: onApri,
        colore: accento.tinta,
        coloreBordo: accento.base.withValues(alpha: .3),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            IconaTonda(
              aggiornata ? Icons.air_rounded : Icons.cloud_off_rounded,
              colore: accento.forte,
              sfondo: superficie,
              dimensione: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titolo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: testo, height: 1.2),
                  ),
                  Text(
                    aggiornata
                        ? s.t('Aria nel parco · ${quandoLettura(st.lastSeen, s)}', 'Park air · ${quandoLettura(st.lastSeen, s)}')
                        : s.t('Dati non aggiornati', 'Data not up to date'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: testoSecondario),
                  ),
                ],
              ),
            ),
            if (temp != null) ...[
              const SizedBox(width: 8),
              Icon(iconaMetrica(Metriche.temperatura), size: 18, color: aggiornata ? accento.forte : testoTenue),
              const SizedBox(width: 2),
              Text(
                formattaValore(temp.value, mTemp, s),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: aggiornata ? testo : testoSecondario),
              ),
            ],
            Icon(Icons.chevron_right_rounded, color: accento.forte),
          ],
        ),
      ),
    );
  }
}

/// Banner di allerta ambientale in Home (arancione o rosso). Non è un
/// pericolo: niente finestra in primo piano, solo il banner. Tocco → Ambiente.
class BannerAllerteAmbiente extends StatelessWidget {
  final StatoAmbiente stato;
  final Copie s;
  final VoidCallback onApri;

  const BannerAllerteAmbiente({super.key, required this.stato, required this.s, required this.onApri});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stato,
      builder: (context, _) {
        final allerte = stato.allerte;
        return AnimatedSize(
          duration: durata(context, 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: allerte.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    children: [
                      for (final al in allerte) ...[
                        _banner(context, al),
                        if (al != allerte.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _banner(BuildContext context, EnvAlert al) {
    final rosso = al.level == EnvLevel.bad;
    final sfondo = rosso ? rossoLivello : aranciaLivello;
    final m = stato.metrica(al.metric);
    final livello = testoLivello(al.level, al.text, s);
    final testoBanner = '${etichettaMetrica(al.metric, s, m)}: ${livello.toLowerCase()}';
    final dettaglio = [if (al.value != null) formattaValore(al.value, m, s), quandoLettura(al.at, s)].join(' · ');
    return Semantics(
      liveRegion: true,
      button: true,
      label: '${s.t('Allerta aria', 'Air alert')}: $testoBanner, $dettaglio',
      excludeSemantics: true,
      child: Material(
        color: sfondo,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onApri,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                const Icon(Icons.masks_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        testoBanner,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(dettaglio, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: .92))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
