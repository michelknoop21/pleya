# P. Reviewherstel van 20 september 2026

Dit document is het duurzame register van de 29 bevindingen uit de onafhankelijke re-baseline-review.
Het bronrapport stond buiten de worktree; deze tabel voorkomt dat de uitvoeringsstand verloren gaat.
Een vinkje betekent hier uitsluitend: productfix aanwezig én de gerichte regressietest was groen.
De brede eindgates zijn na deze herstelronde nog niet opnieuw gedraaid.

## Stand bij pauzeren

| ID | Bevinding | Stand | Gericht bewijs |
| --- | --- | --- | --- |
| C1 | member promoveert zichzelf tot admin | `[x]` | eigen-id rolpatch geweigerd; API-suite groen |
| C2 | bibliotheektitelwijziging wist mediabestanden | `[x]` | ongewijzigde roots behouden location-id en bestanden |
| H3 | config-managed bibliotheek muteerbaar | `[x]` | PATCH en DELETE geven eigen foutcode |
| H4 | refresh-tokenhergebruik doodt sessie niet | `[x]` | sessie, refreshketen en streamsessies ingetrokken |
| H5 | read-only API-token doet adminacties | `[x]` | adminbeslissing controleert rol én scope |
| H6 | admin wijzigt owner-wachtwoord | `[x]` | owner kan alleen eigen wachtwoord wijzigen |
| H7 | login-limiter is globaal vol te houden | `[x]` | oudste bucket wijkt bij volle kaart |
| H8 | Pleya Server-profiel verdwijnt na aanmaken | `[x]` | registry levert local én pleyaServer |
| H9 | twee accounts op dezelfde server botsen | `[x]` | connection-id bevat server-id en user-id |
| H10 | Dart-formatpoort in CI draait nooit | `[x]` | shell-regressietest groen |
| H11 | authority-gate mist inner merge en deletie | `[x]` | volledig mergebereik, commitblob en deletietest groen |
| H12 | Plex negeert gekozen bitrate | `[x]` | preset wint, gemeten verbinding blijft plafond |
| M13 | refresh-purge loopt vast op self-FK | `[x]` | migratietest groen met `ON DELETE SET NULL` |
| M14 | Jellyfin mist ultrawide resolutiecap | `[x]` | één begrensde as schrijft beide condities |
| M15 | relay-uploadlimiet heeft TOCTOU | `[x]` | gelijktijdige en refund-tests groen |
| M16 | offline root verliest inodevertrouwen | `[x]` | onbereikbare root behoudt laatste meting |
| M17 | responsecontractpoort mist geneste refs | `[x]` | `$ref`, `allOf`, `oneOf`, `anyOf` en `items` gedekt |
| M18 | Android houdt oud decoderprofiel | `[x]` | backendwissel ververst capabilities |
| L19 | onbetrouwbare TLS-proxyconfig faalt stil | `[x]` | waarschuwing wordt eenmaal gelogd |
| L20 | nieuwe NTFS-root krijgt inodevertrouwen | `[x]` | root wordt bij aanmaken gemeten |
| L21 | scaninstellingen per bibliotheek ongebruikt | `[x]` | startfilter en eigen interval getest |
| L22 | intrekkingsretentie heeft nul marge | `[x]` | hoogste TTL plus vijf minuten marge |
| L23 | Go-testcontainer ziet hele repo en `.env` | `[x]` | alleen benodigde redactiedata en protocoldoc gemount |
| L24 | webclient bewaart oud refreshtoken | `[x]` | tokenpaar zonder refresh verwijdert bestaand token |
| L25 | rauwe JSON-fout lekt naar loginclient | `[x]` | vaste clienttekst, detail alleen in log |
| L26 | offline-melding noemt verkeerde server | `[x]` | eerste werkelijk offline entry wordt genoemd; bannertests groen |
| L27 | dubbele Nederlandse i18n-sleutel | `[x]` | duplicate-key-test groen; `strings_nl.g.dart` ongewijzigd |
| L28 | `Vary: Origin` ontbreekt zonder Origin | `[x]` | header wordt vóór de vroege return gezet |
| L29 | mislukte git-aanroep laat commit stil weg | `[x]` | `sh`-argumentvorm faalt op non-zero; lege sha geeft `UI.user_error!`; minitest groen |

Telling: **29 gericht groen**.

De completionbasis is gecommit als `0b9699ec`; de 26 afgeronde fixes en hun regressiedekking als
`3734e399`. De lokale CI-check (`scripts/ci_checks.sh`) was voor `3734e399` volledig groen.

## Exact hervatpunt

Alle 29 bevindingen zijn gesloten in de commits na `ca595d68`; zie `git log ca595d68..` voor de
drie herstelcommits.

## Wat na de 29 punten nog resteert

- Brede verificatie na de laatste wijziging: codegen, `scripts/ci_checks.sh`, volledige Fluttertests,
  alle Go-packages, protocol/responsevalidatie, web check/test/build, Pleya Verify en de volledige
  clean-checkoutgate van `pleya_server/scripts/verify-local.sh`.
- Release notes opnieuw genereren en de authority-gate tegen mergecommit `0b9699ec` draaien.
- Daarna pas de veiliggestelde S2.4- en loudnesswijzigingen terugbrengen en opnieuw verifiëren.
- Het totale Pleya Server-plan is hiermee niet af. De laatste volledig getelde masterlijstbaseline
  had 127 open taken; die telling moet na het landen van deze merge opnieuw worden gereconcilieerd.
