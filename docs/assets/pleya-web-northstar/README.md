# Pleya Web northstar, kandidaatset van 4 september 2026

Status: **CANDIDATE**. Niet goedgekeurd, geen implementation authority tot Michel de set in de
chat goedkeurt. Wat hier staat is de eerste complete web-familie van de Unified 2026-designtaal:
40 schermen, 80 beelden, elk uit één HTML-bron in `src/pages/`.

Bijgewerkt op 4 september 2026 na reviewronde 3 (`C-northstar-review.md` C.5): de vijf schermen
van de uitgebreide scope (17, 18, 19, 28, 35) zijn gereviewd en gecorrigeerd, en de hele set is
opnieuw gerenderd omdat drie van die bevindingen in `web.css` zaten. Zes schermen ontbreken nog
en staan onderaan dit bestand.

## Wat de set is

Een browserinterface die familie is van de TV-set (`docs/assets/tvos-unified/` op `main`,
goedgekeurd 3 september) en de iOS-set (`docs/assets/ios-unified/` op `feat/netflix-mobile`,
DEC-090), zonder een uitgerekte telefoon of een uitgezoomde televisie te worden:

- **≥ 900 breed**: de topnav van de TV-familie op webmaat (wordmark links, cluster in het
  midden, zoeken en avatar rechts), met een amberkleurige Beheer-pil voor eigenaar en beheerder.
- **< 900 breed**: de kop en de vijfslots-tabbalk van de iOS-familie (Home · Series · Films ·
  Boeken · Mijn Pleya), waarbij Boeken alleen verschijnt als er een zichtbare boekenbibliotheek
  is (DEC-094 op `feat/ebooks`).
- Tokens uit `pleya_web/src/styles/tokens.css`, die per regel naar `lib/theme/mono_theme.dart`
  verwijst. `src/web.css` documenteert elke afwijking die alleen op een browserbreedte bestaat.
- Serverbeheer is dezelfde designsysteemlaag met een eigen zijbalk en een tabelprimitief; het
  is herkenbaar als beheer door dichtheid en inhoud, niet door een tweede kleurenschema.

De getoonde titels en hun artwork zijn niet bindend. Films en series komen uit dezelfde
TMDb-artmap die de TV- en iOS-mockups gebruiken (buiten git, `~/Downloads/mockups/_src/art`);
boekcovers zijn CSS-getekend, zoals de e-booksgoldens, omdat commerciële covers niet in de
repository horen.

## Manifest

Breedtes: 1600 (brede desktop), 1280 (compacte desktop), 1024 (tablet-breedte browser),
393 (iPhone 15 Pro, op 2×). Een telefoonbeeld is één schermvulling met de tabbalk onderaan; een
breed beeld is de hele pagina.

| Nr | Scherm | Breedtes | Bron | Bijzonderheid |
| --- | --- | --- | --- | --- |
| 01 | Home | 1600, 1280, 1024, 393 | `01-home.html` | hero, Verder kijken, Verder lezen, Volgende afleveringen, per bibliotheek, Nieuw in Boeken |
| 02 | Films-landing | 1600, 1024, 393 | `02-films.html` | geen Verder kijken (DEC-086 op main) |
| 03 | Series-landing | 1600, 393 | `03-series.html` | Volgende afleveringen 16:9 vooraan |
| 04 | Boeken-landing | 1600, 1280, 1024, 393 | `04-boeken.html` | Verder lezen als liggende kaart met cover-ambience |
| 05 | Alle films | 1600, 393 | `05-alle-films.html` | filters, sorteren, hover op de eerste kaart |
| 06 | Zoeken | 1600, 393 | `06-zoeken.html` | secties Films, Boeken, Afleveringen, Auteurs |
| 07 | Zoeken zonder resultaat | 1600, 393 | `07-zoeken-leeg.html` | uitweg in plaats van een dood spoor |
| 08 | Filmdetail | 1600, 1024, 393 | `08-film-detail.html` | versiekiezer, sporen, bestand |
| 09 | Seriedetail | 1600, 393 | `09-serie-detail.html` | seizoenchips, afleveringsrijen met voortgang |
| 10 | Boekdetail | 1600, 1024, 393 | `10-boek-detail.html` | Lees verder, Downloaden, reeks |
| 11 | Mijn Pleya | 1600, 393 | `11-mijn-pleya.html` | persoonlijke laag, toestellen, ingang naar beheer |
| 12 | Inloggen | 1600, 393 | `12-inloggen.html` | foutstaat na afgewezen poging |
| 13 | Lege bibliotheek | 1600, 393 | `13-lege-bibliotheek.html` | beheerder ziet de knop, lid alleen de uitleg |
| 14 | Server onbereikbaar | 1600, 393 | `14-server-offline.html` | sessie blijft, geen uitlogscherm |
| 15 | Laden | 1600, 393 | `15-skeleton.html` | skelet in de maten van de echte kaarten |
| 16 | Kaartstaten | 1600 | `16-kaartstaten.html` | referentieblad: rust, hover, focus, voortgang, gezien, nieuw, versies, geen artwork |
| 17 | Verzamelingen en afspeellijsten (PS-9C) | 1600, 393 | `17-collecties.html` | vierluik, segment links en sortering rechts (S19) |
| 18 | Afspeellijst (PS-9C) | 1600, 393 | `18-afspeellijst.html` | geordend, kijkstatus per rij, herordenen als eigen modus (S19) |
| 19 | Kijkgeschiedenis, favorieten, waarderingen (PS-9P) | 1600, 393 | `19-geschiedenis-favorieten.html` | cijfer 1 tot 10 los van de providerscore, geschiedenis zelf te wissen (S20) |
| 20 | Beheer: overzicht | 1600, 1280, 393 | `20-admin-overzicht.html` | waarschuwing, vier tellers, activiteit, nu aan het kijken |
| 21 | Beheer: bibliotheken | 1600, 393 | `21-admin-bibliotheken.html` | CRUD, scan per rij, `.env`-overname |
| 22 | Beheer: bibliotheek bewerken | 1600, 393 | `22-admin-bibliotheek-bewerken.html` | roots uit opsomming, soort vast bij inhoud, toegang, verwijderen |
| 23 | Beheer: verwijderen bevestigen | 1600, 393 | `23-admin-bibliotheek-verwijderen.html` | naam typen om te bevestigen |
| 24 | Beheer: opslag | 1600, 393 | `24-admin-opslag.html` | foutstaat verdwenen root, inodevertrouwen |
| 25 | Beheer: scans en taken | 1600, 393 | `25-admin-scans.html` | lopende scan, fouten met retry, geschiedenis |
| 26 | Beheer: gebruikers | 1600, 393 | `26-admin-gebruikers.html` | vier rollen |
| 27 | Beheer: gebruiker | 1600, 393 | `27-admin-gebruiker.html` | rechtenladder per bibliotheek, toestellen, verwijderen |
| 28 | Beheer: media en streaming | 1600 | `28-admin-media.html` | drie hwaccel-backends runtime gedetecteerd, ondertitelbeleid, downloads (S1, S18, S23) |
| 29 | Beheer: metadata en artwork | 1600 | `29-admin-metadata.html` | sidecar-dekking met 80%-poort, artworkcache, providerplek |
| 30 | Beheer: netwerk | 1600 | `30-admin-netwerk.html` | servernaam, publiek adres; host-config alleen-lezen |
| 31 | Beheer: beveiliging | 1600, 393 | `31-admin-beveiliging.html` | token-TTL's, alle sessies, sleutelrotatie |
| 32 | Beheer: diagnostiek | 1600 | `32-admin-diagnostiek.html` | versies, capabilities, gezondheid, omgeving, geredigeerde log |
| 33 | Beheer op een telefoon | 393 | `33-admin-mobiel-index.html` | de zijbalk als lijst |
| 34 | Beheer: agents en API-tokens | 1600, 393 | `34-admin-agents.html` | MCP-status, tokens als sessies, bereik, auditlog van agentacties |
| 35 | Beheer: onderhoud (PS-11B) | 1600, 393 | `35-admin-onderhoud.html` | back-up als instelling met failure-domain-waarschuwing, hersteltest, upgradepad, faalpaden (S25) |
| 40 | Setup 1: eigenaar | 1600, 393 | `40-setup-eigenaar.html` | setupcode, account, servernaam |
| 41 | Setup 2: opslag | 1600 | `41-setup-opslag.html` | roots uit de mounts |
| 42 | Setup 3: bibliotheek | 1600, 393 | `42-setup-bibliotheek.html` | drie soorten |
| 43 | Setup 4: scannen | 1600 | `43-setup-scan.html` | voortgang, eerste titels |
| 44 | Na de setup | 1600, 393 | `44-setup-klaar.html` | Home met één bibliotheek, geen lege rijen |

## Nog te tekenen

Zes schermen ontbreken en gaan in één ronde naar Michel (poort P3 in
`docs/PLEYA-SERVER-MASTERLIST.md`). Ze staan met hun route, data en slice in deel D.5.

| Nr | Scherm | Slice |
| --- | --- | --- |
| 11b | Downloads op Mijn Pleya | S23 |
| 36 | Beheer: metadata-match en per-field overrides | S22 |
| 37 | Beheer: transcode-sessies | S18 |
| 38 | Beheer: realtime-status | S21 |
| 50 | Browserspeler | S13 |
| 51 | Webreader op `@readium/navigator` | S12 |

## Nabouwen en uitbreiden

`DESIGN.md` in deze map is de handleiding: tokens met bron, het layoutcontract per breedte, de
macrotaal van `build.mjs`, de componentmapping naar `pleya_web`, de artwork- en fixturebronnen
en een stappenplan voor een nieuw scherm.

## Opnieuw bouwen

```
cd docs/assets/pleya-web-northstar/src
node build.mjs            # alles
node build.mjs 01 20      # alleen deze nummers
```

Playwright komt uit de globale installatie onder `/opt/homebrew` (1.61), net als bij de TV-set.
`out/` is wat `build.mjs` schrijft en staat niet in git. Artwork komt uit `~/Downloads/mockups/
_src/art` met `~/Downloads/mockups-tvos/_src/art` als terugval; `PLEYA_ART=` overrulet dat.

## Wat een goedkeuring vastlegt

De compositie, hiërarchie en maatvoering per scherm, de shellkeuze per breedte, de kaartstaten
uit 16, en de grens tussen consumer en beheer. Niet de titels, het artwork, de aantallen in de
beheerschermen of de exacte teksten in waarschuwingen. Een implementatie wordt tegen deze
beelden en tegen deel D van `docs/pleya-server-rebaseline/` beoordeeld.

Twee open designdetails uit DEC-090 zijn hier voor web als volgt ingevuld en vragen bij
goedkeuring een expliciet ja: de secundaire hero-knop is **Meer info** (het TV-contract) en de
carousel draagt een tijdelijke segmentindicator, geen permanente dots.
