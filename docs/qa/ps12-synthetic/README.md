# PS-12 synthetische droogloop

Hoort bij [het migratievoorstel](../../pleya-server-plex-migration-proposal.md) (S15.9, DEC-168).
PS-12 is niet vrijgegeven. Dit is geen productcode, geen commando en geen bewijs dat een echte
migratie werkt: het laat zien dat de regels uit het voorstel op verzonnen data de uitkomst geven die
het voorstel belooft, en waar ze dat niet doen.

Alles is verzonnen: de Plex-server `plex-fictief-01`, de accounts `anouk-fictief`, `bram-fictief`,
`cas-fictief` en `dirk-fictief`, de titels, de tmdb-nummers en de UUID's. Er is geen token, geen
netwerkverkeer en geen database.

## Draaien

Vanuit de root van de repo:

```bash
python3 -I docs/qa/ps12-synthetic/dryrun.py
```

Alleen de standaardbibliotheek. Exitcode 0 als alle controles slagen, 1 als er een faalt. Twee
opeenvolgende runs geven byte voor byte dezelfde uitvoer (gecontroleerd met `cmp`).

| Bestand | Inhoud |
|---|---|
| `fixture.json` | Plex-antwoorden per gebruiker in de vorm van `/library/sections/{id}/all` (`MediaContainer.Metadata`), de serie als `/library/metadata/{id}?includeGuids=1`, en `/accounts`. De Pleya-kant is een snapshot met de kolommen van `media_items`, `metadata_candidates`, `users`, `library_permissions` en `watch_states`, plus de koppeltabel en de door de eigenaar bevestigde titel/jaar-matches. |
| `dryrun.py` | Droogloop, schrijfronde in het geheugen en zes scenario's (A tot F). |

## Wat het script nadoet

De matchstappen volgen `lib/services/unified_catalog/grouping_service.dart` met de hulpfuncties uit
`identity_evidence.dart`, `canonical_media_identity.dart` en `lib/utils/title_normalizer.dart`:
dezelfde normalisatie van titels, dezelfde bucketsleutel, `normalizeStableGuid`, tokens als
`scope:namespace:waarde` met `/sXeY` achter de serie-id voor afleveringen, de C19-regel per bron en
de tokenbotsing die de zwakke stap blokkeert. Aan de Pleya-kant bestaan alleen tmdb-tokens, en alleen
voor films en series met `metadata_candidates.state = 'matched'`, omdat de server niet meer opslaat.

De Python-versie is een naslag, geen tweede implementatie die meegaat: wijzigt de Dart-regel, dan
loopt dit script achter tot iemand hem bijwerkt.

Een nieuwe `watch_states`-rij krijgt in de simulatie:

| Kolom (0004) | Waarde | Status |
|---|---|---|
| `subject` | Pleya-gebruiker uit de koppeltabel | volgt uit het voorstel |
| `item_id` | Pleya-item na een zekere of bevestigde match | volgt uit het voorstel |
| `position_ms` | `viewOffset`, anders 0 | voorlopig |
| `duration_ms` | Plex-`duration` | open besluit 13 in het voorstel |
| `watched` | `viewCount >= 1` | voorlopig |
| `play_count` | `viewCount` | open besluit 4 |
| `revision` | 1 (0 betekent volgens 0004 "nog geen canonieke toestand") | voorlopig |
| `owner_session_id`, `owner_lease_until` | NULL | volgt uit het voorstel: een import neemt geen playback over |
| `last_explicit_at`, `last_explicit_kind` | NULL | open besluit 6 |

`created_at` en `updated_at` laat de simulatie weg. `lastViewedAt` gaat alleen naar het journaal; of
het ook in `last_played_at` uit 0017 hoort is open besluit 5.

Conflictregel in het script: bestaat er al een Pleya-rij voor dezelfde gebruiker en hetzelfde item,
dan is dat een conflict en wordt er niets geschreven. Dat is de strengste variant uit open besluit 3,
niet de gekozen variant.

## Wat de fixture afdekt

| Bronrij | Bedoeld geval |
|---|---|
| anouk 101, tweemaal in de lijst | dubbele rij in de bron (paginaherhaling), eerste wint |
| anouk 102 `Lichtjaar Nul` tegenover Pleya `Lichtjaar Nul (2022)` | alleen titel/jaar, door de eigenaar bevestigd; `(2022)` valt weg bij normaliseren |
| anouk 126 `Wolkenkrabber` | alleen titel/jaar, niet bevestigd |
| anouk 103 en bram 104 `Het Veerpont` 1998 en 2021 | remake: zelfde titel, ander jaar en andere tmdb |
| anouk 105 `Polderlicht` | Pleya heeft de film in twee bibliotheken met dezelfde tmdb |
| anouk 113 `Grijze Duinen` | zelfde, maar zonder tmdb: C19 in de titel/jaar-bucket |
| anouk 112 `Stille Haven` | titel en jaar gelijk, tmdb botst |
| anouk 109 en 110, bram 109 `Kanaalkust` | afleveringen via serie-tmdb plus seizoen en aflevering; bij anouk een bestaande Pleya-positie en een lopende lease |
| anouk 141 en 142 `Morgenland` | Plex heeft de film in twee bibliotheken, beide landen op hetzelfde Pleya-item |
| anouk 124, 125 | positie voorbij de duur, `lastViewedAt` na het snapshotmoment |
| anouk 122 | muziektrack |
| bram 101 | Pleya-status bestaat al (revision 3) |
| bram 130 | geen kijkstatus in de bron |
| cas 103 | Plex gaf toegang, de Pleya-rol `restricted` heeft geen recht op die bibliotheek |
| dirk 101 | Plex-account zonder koppeling |

`dirk-fictief` staat voor een Plex-gebruiker wiens rijen wel binnenkomen maar die niet gekoppeld is.
Of je de kijkstatus van een gedeelde gebruiker buiten Plex Home überhaupt kunt lezen, staat als niet
geverifieerd in het voorstel.

## Uitvoer

Gedraaid op 30 oktober 2026 met Python 3.13.12, ongewijzigd overgenomen:

```text
== A. Droogloop ==
plan-digest 6321993c69ecded7, dubbele bronrijen genegeerd: 1
  nieuw            anouk-fictief  1/101 De Zoutpan               sterk token
  nieuw            anouk-fictief  1/102 Lichtjaar Nul            titel/jaar, door eigenaar bevestigd
  nieuw            anouk-fictief  1/103 Het Veerpont             sterk token
  overgeslagen     anouk-fictief  1/105 Polderlicht              2 Pleya-items delen een sterk token
  conflict         anouk-fictief  1/109 Kanaalkust S1E1          Pleya heeft al status (revision 2)
  conflict         anouk-fictief  1/110 Kanaalkust S1E2          actieve Pleya-playback (lease loopt)
  geen titelmatch  anouk-fictief  1/112 Stille Haven             titel/jaar gelijk, maar tmdb botst
  overgeslagen     anouk-fictief  1/113 Grijze Duinen            C19: 2 Pleya-items in bucket movie:grijzeduinen:2012
  geen titelmatch  anouk-fictief  1/120 Onbekende Reis           geen titel/jaar-kandidaat
  overgeslagen     anouk-fictief  1/122 Havenlied                niet ondersteund: track
  overgeslagen     anouk-fictief  1/124 Avondrood                ongeldige positie
  overgeslagen     anouk-fictief  1/125 Morgenland               ontbrekende of toekomstige lastViewedAt
  overgeslagen     anouk-fictief  1/126 Wolkenkrabber            alleen titel/jaar, wacht op bevestiging
  conflict         anouk-fictief  1/141 Morgenland               2 Plex-rijen voor hetzelfde Pleya-item
  conflict         anouk-fictief  1/142 Morgenland               2 Plex-rijen voor hetzelfde Pleya-item
  conflict         bram-fictief   2/101 De Zoutpan               Pleya heeft al status (revision 3)
  nieuw            bram-fictief   2/103 Het Veerpont             sterk token
  nieuw            bram-fictief   2/104 Het Veerpont             sterk token
  nieuw            bram-fictief   2/109 Kanaalkust S1E1          sterk token
  overgeslagen     bram-fictief   2/130 Zomerdijk                geen kijkstatus in de bron
  nieuw            cas-fictief    3/111 Bosuil en Bever          sterk token
  overgeslagen     cas-fictief    3/103 Het Veerpont             geen recht op de Pleya-bibliotheek
  overgeslagen     dirk-fictief   4/101 De Zoutpan               Plex-gebruiker niet gekoppeld
Totaal: nieuw 7, conflict 5, overgeslagen 9, geen titelmatch 2
  anouk-fictief  nieuw 3, conflict 4, overgeslagen 6, geen titelmatch 2
  bram-fictief   nieuw 3, conflict 1, overgeslagen 1, geen titelmatch 0
  cas-fictief    nieuw 1, conflict 0, overgeslagen 1, geen titelmatch 0
  dirk-fictief   nieuw 0, conflict 0, overgeslagen 1, geen titelmatch 0
  [ok] droogloop schrijft niets (bron en doelsnapshot onaangeroerd)

== B. Eerste schrijfronde ==
  {'geschreven': 7, 'al toegepast': 0, 'conflict bij schrijven': 0}, store f5aa58a43f0be727 -> 93ee4e2aa006f694, journaal 7
  [ok] alleen 'nieuw' wordt geschreven
  [ok] bestaande Pleya-rij 01 van a2 ongewijzigd
  [ok] bestaande Pleya-rij 09 van a1 ongewijzigd
  [ok] bestaande Pleya-rij 10 van a1 ongewijzigd

== C. Tweede run met hetzelfde plan ==
  {'geschreven': 0, 'al toegepast': 7, 'conflict bij schrijven': 0}, store 93ee4e2aa006f694, journaal 7
  [ok] droogloop geeft dezelfde uitkomst
  [ok] geen tweede schrijfactie, store gelijk
  [ok] journaal zonder dubbele eenheden

== D. Afbreken halverwege en hervatten ==
  afgebroken voor commit van eenheid 4; geschreven tot dan: 3
  hervat: {'geschreven': 4, 'al toegepast': 3, 'conflict bij schrijven': 0}, store 93ee4e2aa006f694, journaal 7
  [ok] hervatten slaat de al gecommitte eenheden over
  [ok] eindtoestand gelijk aan een ononderbroken run
  [ok] geen dubbele journaalregels na hervatten

== E. Twee gebruikers, zelfde titel ==
  Het Veerpont 1998: anouk watched=True pos=0, bram watched=False pos=1200000
  [ok] elk krijgt de eigen Plex-status
  Kanaalkust S1E1: anouk pos=1500000 (bestond al), bram watched=True
  [ok] anouks bestaande Pleya-positie blijft staan
  [ok] elke geschreven rij komt van het Plex-account dat aan dat subject gekoppeld is
  [ok] plan per gebruiker los berekend is gelijk aan het gezamenlijke plan

== F. Pleya-kijkactie tussen droogloop en schrijven ==
  {'geschreven': 6, 'al toegepast': 0, 'conflict bij schrijven': 1}
  [ok] de nieuwe Pleya-actie blijft staan, de import schrijft daar niets

alle controles geslaagd
```

## Wat de uitvoer zegt

Van de 23 unieke bronrijen worden er 7 geschreven. Dat lage aandeel is opzet: de fixture bestaat
vooral uit randgevallen. Over een echte bibliotheek zegt het niets.

Idempotentie rust op twee wachters. De sleutel `sha256(plandigest|gebruiker|item|handeling)` in het
journaal herkent een eenheid die al gecommit is, en de revisiecontrole weigert te schrijven als de
doelrij sinds de droogloop veranderd is. In run C slaat de eerste wachter alle zeven eenheden over.
Zonder journaalcontrole zou de revisiecontrole ze alsnog tegenhouden, maar dan als "conflict bij
schrijven" in plaats van "al toegepast", en dat maakt een hervat rapport onleesbaar.

Scenario D breekt af nadat de rij van eenheid 4 klaargezet is maar vóór de commit. Rij en
journaalregel worden in één stap vastgelegd, dus na het afbreken staan er precies drie, en het
hervatten schrijft de overige vier.

Scenario E rekent het plan ook per Plex-account los uit en vergelijkt dat met het gezamenlijke plan.
Ze zijn gelijk: de uitkomst voor de ene gebruiker hangt niet af van de bronrijen van een ander.

## Zijn de controles niet loos?

Vier bewuste fouten, elk in een kopie van het script buiten de repo, met de controles die daarop
rood werden:

| Mutatie | Rode controles |
|---|---|
| rij vastleggen vóór het afbreken, journaal pas erna | "hervatten slaat de al gecommitte eenheden over", "geen dubbele journaalregels na hervatten" |
| rijen van `bram-fictief` aan de Pleya-gebruiker van `anouk-fictief` koppelen | vijf controles, waaronder "elk krijgt de eigen Plex-status" en "plan per gebruiker los berekend is gelijk aan het gezamenlijke plan" |
| revisiecontrole bij schrijven uitgezet | "de nieuwe Pleya-actie blijft staan, de import schrijft daar niets" |
| journaalcontrole uitgezet | "hervatten slaat de al gecommitte eenheden over" |

## Wat dit niet afdekt

- Echte Plex-antwoorden. De veldnamen komen uit `lib/services/plex_mappers.dart` en
  `test/fixtures/plex_detail/`, de waarden zijn verzonnen.
- Een tweede droogloop ná de import. Die ziet de geïmporteerde rijen als bestaande Pleya-status en
  meldt ze als conflict; het voorstel beschrijft hoe het journaal dat als "al geïmporteerd" kan
  herkennen, maar het script doet dat niet.
- Postgres-transacties, de lease-logica van `internal/watch` en `play_history` uit 0020.
- Favorieten, waarderingen, collecties en afspeellijsten.
- Plex-sleutels die tussen twee snapshots veranderen.
