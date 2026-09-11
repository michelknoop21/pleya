# Design-index: welke northstar geldt, waar staat hij, en wat is de volgende stap

Aangemaakt op 5 september 2026. Dit bestand beantwoordt drie vragen die tot nu toe
alleen te beantwoorden waren door vier branches en dertien documenten naast elkaar te
leggen:

1. Welke beeldenset is bindend voor welk oppervlak, en welke is geschiedenis.
2. Waar staat die set, en op welke branch.
3. Wat is de eerstvolgende stap, en wie bezit hem.

Het vervangt geen enkel bestaand document. Het wijst ze aan en zegt welke autoriteit
heeft. Bij tegenspraak wint het document waar hier naar verwezen wordt, niet deze index.

---

## 1. Vier oppervlakken, vier sets

| Oppervlak | Set | Aantal | Staat | Waar | Branch |
|---|---|---|---|---|---|
| **tvOS** | `docs/assets/tvos-unified/` | 5 mappen | **actief** | zie §2 | `main` |
| **iOS en mobiel** | `docs/assets/ios-unified/northstar/` | 21 schermen plus 5 comps | **staat op `main`** sinds `011ffdbf`; fase 1 tot en met 3 gebouwd via PR #5 (`70ec21b5`) | §3 | `main` |
| **Pleya Web** | `docs/assets/pleya-web-northstar/` | 46 schermen plus bron | getekend, niet geland | alleen op de branch | `integration/pleya-server-rebaseline` |
| **Ebooks** | `docs/assets/ebooks/northstar/` | 9 schermen plus bron | getekend, niet geland | alleen op de branch | `feat/ebooks` |

**Bijgewerkt 11 september 2026:** de iOS-set staat op `main` sinds PR #5, en `feat/netflix-mobile`
is niet meer de tak die landt ([DEC-106](DECISIONS.md#dec-106)). Wat er van iOS en tvOS nog moet
gebeuren voor deze redesign af is, staat sinds die datum in
[unified-2026-closure.md](unified-2026-closure.md), met de iOS-status in
[ios-unified-implementation-register.md](ios-unified-implementation-register.md) en de tvOS-status
in [tvos-redesign-register.md](tvos-redesign-register.md).

Alleen tvOS en iOS staan op `main`. De andere drie leven uitsluitend op hun eigen branch, en
dat is de spreiding die dit document zichtbaar maakt. Zie §9 voor wat daaraan te doen is.

`feat/pleyaserver` draagt een oudere kopie van de webset en mist 91 tvOS-bestanden die
`main` wel heeft. `integration/pleya-server-rebaseline` is de nieuwere van de twee: die
staat op `main` plus de webset, zonder achterstand.

Drie branches dragen **geen enkel** uniek designbestand en lopen alleen achter:
`provenance/netflix-redesign-f8e0e59`, `shared/unified-media-core` en `fix/tvos-art1`.
Daar valt niets te redden.

---

## 2. tvOS, de enige set die vandaag bindt

Vier mappen onder `docs/assets/tvos-unified/`, en ze zijn niet gelijkwaardig.

| Map | Beelden | Rol | Autoriteit |
|---|---|---|---|
| `northstar/` | 01 tot en met 08 | de oorspronkelijke acht, **deels superseded** | [DEC-065](DECISIONS.md#dec-065), plus hoofdstuk 33 van [tvos-unified-experience.md](tvos-unified-experience.md) |
| `approved-2026-09-03/` | 09 tot en met 25 | goedgekeurd doelbeeld | [tvos-redesign-09-25-approved.md](tvos-redesign-09-25-approved.md) |
| `mockups-2026-09-04/` | 26 tot en met 31 | goedgekeurd, **nieuwste** | DEC-092 tot en met DEC-096 |
| `mockups-2026-09-02/` | Mijn Pleya-secties | goedgekeurd voor die secties | de audits in §5 |
| root, vijf `*-reference.png` | los | **historisch**, voorloper van de northstar | alleen `home-reference` en `source-picker-reference` worden nog genoemd |
| `src/` | HTML-bron | waar de beelden uit gerenderd worden | `build.mjs` en `tv.css` |

### Wat er superseded is, en waardoor

Dit is het stuk dat het vaakst misgaat, want de beelden zelf zeggen het niet.

| Beeld | Wat vervalt | Waardoor | Notitie staat in |
|---|---|---|---|
| `01-home.jpg` | de hero als afgeronde kaart ín de pagina, "nooit full bleed" | [DEC-095](DECISIONS.md#dec-095) | hoofdstuk 33.1 |
| `02-home-rail-focus.jpg` | de onderste strook met afgeronde hoeken, het raillabelanker op 372 | [DEC-095](DECISIONS.md#dec-095) | hoofdstuk 33.2 |
| `02-home-rail-focus.jpg` | de drie absolute maten: band 400, gefocust 711, buren 267 | [DEC-087](DECISIONS.md#dec-087) | hoofdstuk 33.2 |
| `03-films-landing.jpg` | de kaarttaal op de landing | [DEC-064](DECISIONS.md#dec-064) | hoofdstuk 33.3 |
| `04-series-landing.jpg` | idem | [DEC-064](DECISIONS.md#dec-064) | hoofdstuk 33.4 |

Elk van die notities staat als blockquote onder de betreffende paragraaf in hoofdstuk 33.
De beelden zijn bewust **niet** opnieuw gerenderd: de tekst in de PNG en de hash eronder
zouden dan wijzigen, en de rest van wat het beeld vastlegt blijft gewoon geldig.

**De vuistregel.** Voor Home is `mockups-2026-09-04/30-home-*` bindend voor de
compositie. Voor alles wat 01 en 02 daarnaast vastleggen zijn die twee nog steeds
bindend. Voor 09 tot en met 25 is het approval-manifest de statusautoriteit en niet de
tekst "candidate" die nog in de PNG's staat.

---

## 3. iOS en mobiel

**Branch:** `main`, sinds PR #5 (`70ec21b5`, 6 september 2026).
**Autoriteit:** [DEC-090](DECISIONS.md#dec-090), "iOS Unified 2026 northstar bevroren, 21 mockups
bindend voor de iPhone-interface".

| Wat | Waar |
|---|---|
| 21 genummerde beelden, bevroren op `011ffdb` | `docs/assets/ios-unified/northstar/01-…` tot en met `21-activiteit.png` |
| 5 Home-comps, met een naam en geen nummer zodat de bevroren set de 21 blijft | `home-comp`, `home-comp-gefilterd`, `profiel-laden-comp`, `serie-detail-comp`, `mijn-pleya-comp` |
| hashes | `SHA256SUMS` in dezelfde map |
| de audit die de set vaststelde | `docs/ios-unified-2026-audit.md`, 266 regels, status bevroren |
| de gebouwde fasen 1 tot en met 3 | `docs/ios-unified-2026-fase1-plan.md`, `-fase2-plan.md`, `-fase3-plan.md` |
| de iOS-status per scherm en de resterende bouwronden | [ios-unified-implementation-register.md](ios-unified-implementation-register.md) |

**De Home-compositie zit niet in de 21-set.** De autoriteit daarvoor zijn de vijf comps
plus paragraaf 10 van het auditrapport. Waar comp en mockup elkaar raken wint de mockup.

### Archeologie: `feat/netflix-mobile`

Die branch bouwde fase 2 tot en met 4 zelfstandig, los van de tak die uiteindelijk in PR #5 landde,
en wordt niet gemerged: zie [DEC-106](DECISIONS.md#dec-106) voor de volledige reconstructie. Hij
blijft staan als leesbaar referentiemateriaal, niet als bron voor een merge. Zoeken, wat op die
branch fase 4 was, wordt opnieuw gebouwd op de componenten die wel op `main` staan.

### Stand en volgende stap

Fase 1 tot en met 3 zijn gebouwd en staan op `main`: de iPhone-Home als eigen scherm (DEC-102,
DEC-103), Series- en Films-landing als eigen bestemming (DEC-104), en Alle films/Alle series met
de filtersheet (DEC-105). De twee open Home-details uit paragraaf 10 van de audit zijn gesloten
door [DEC-110](DECISIONS.md#dec-110).

De volledige werkvolgorde voor wat er nog moet gebeuren, van Zoeken tot de fysieke
hardware-eindronde, staat in [unified-2026-closure.md](unified-2026-closure.md) (§5). De
schermstatus per nummer staat in
[ios-unified-implementation-register.md](ios-unified-implementation-register.md).

---

## 4. Ebooks

**Branch:** `feat/ebooks`, 33 commits vóór en 128 achter `main`.
**Autoriteit:** DEC-094 op die branch plus het manifest in
`docs/assets/ebooks/northstar/README.md`, dat per beeld de status draagt.

Deze set hangt bewust onder de iOS-set: waar de e-bookscomp en de iOS Unified 2026-set
elkaar raken, **wint de iOS-set voor de uitvoering** (shell, tabbalk, header, kaarten,
chips, typografie, tokens) **en de comp voor de e-bookinhoud**. Ebooks kan dus niet vóór
iOS landen zonder die volgorde om te draaien.

### Drie soorten beeld, en ze zijn niet hetzelfde

Het manifest onderscheidt ze zelf, en dat onderscheid is de kern van deze set:

1. **Design north star**, `ebooks-northstar-comp.png`: twaalf iPhone-panelen, door Michel
   op 3 september aangeleverd als bindende inhoudelijke bron. Bron, niet ter goedkeuring.
2. **Schermgolden**: één mockup per venster op de echte iPhone 15 Pro-viewport
   (1179 bij 2556). Dit is het ontwerpcontract voor dat ene venster, en het gaat pas op
   `approved` na een expliciet akkoord van Michel. `proposed` betekent: nog niet bouwen.
3. **Executable golden**: een screenshot uit de draaiende app onder een Pleya
   Verify-fixture. Die staat niet in deze map maar in de evidencebundel van het scenario,
   en bewaakt de regressie ná het bouwen.

### Stand

Van de 26 manifestrijen staan er **24 op approved**, één is vervangen (`01-books-home`
door `01b`) en één is de bron. Acht schermen zijn tegen hun goedgekeurde golden gebouwd:

| Golden | Scherm | Gebouwd |
|---|---|---|
| 01b | Boeken-home | ja |
| 02 | Alle boeken | ja |
| 03 | Filtersheet | ja |
| 04 | Boeken zoeken | ja |
| 05 | Boekdetail | ja |
| 06 | Inhoudsopgave | ja |
| 07 | Reader | ja |
| 08 | Leesinstellingen | ja |

De comp tekent twaalf panelen, dus vier onderwerpen uit de north star hebben nog geen
schermgolden: zoeken in boek, downloads, aanbevelingen en boekeninstellingen.

### Volgende stap

Die vier resterende vensters als schermgolden voorstellen, akkoord vragen, en dan bouwen.
De werkwijze staat vast en werkt: `proposed`, akkoord, `approved`, bouwen tegen de golden.

---

## 5. Pleya Web

**Branch:** `integration/pleya-server-rebaseline`, dat is main plus de webset zonder
achterstand. `feat/pleyaserver` draagt een oudere kopie en mist 91 tvOS-bestanden.

46 schermen in `docs/assets/pleya-web-northstar/`, met de HTML-bron ernaast, plus
`DESIGN.md` en `README.md` in dezelfde map. De set is op 4 september compleet verklaard:
de zes ontbrekende schermen (downloads, metadata-match, transcodesessies, realtime,
browserspeler en webreader) zijn toen getekend.

**Deze set is hier niet in dezelfde diepte in kaart gebracht als tvOS, iOS en ebooks.**
Hij hoort bij de Pleya Server-roadmap en niet bij de Netflix-redesign, en heeft zijn eigen
review- en specdocumenten in `docs/pleya-server-rebaseline/`.

---

## 6. Waar de volgende stap staat, en wie welk document bezit

De werkvolgorde voor zowel iOS als tvOS, de statusladder, de bewijsregel, de releasegate en het
protocol van de fysieke eindronde staan sinds 11 september 2026 in één document:
[unified-2026-closure.md](unified-2026-closure.md). Dit is de canonical volgorde; geen ander
document in deze kaart bezit hem nog.

Drie andere documenten dragen de status per workitem, en verwijzen voor volgorde en gate terug naar
de closure:

| Document | Wat het bezit |
|---|---|
| [ios-unified-implementation-register.md](ios-unified-implementation-register.md) | de iOS-status per scherm uit de 21-set en de 5 comps |
| [tvos-redesign-register.md](tvos-redesign-register.md) | het bouwen van mockup 09 tot en met 25, plus de systemische eigenaren eronder |
| [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md) | de masterlijst van alles wat op hardware gezien is, en elk los verzoek van Michel |

**Twee rijen staan in zowel het tvOS-register als de correctieronde**: SYS-1 en SYS-4. Het
register bezit ze als werkitem, de correctieronde als hardwarebevinding. Dat is de afgesproken
werkverdeling en geen dubbeling, maar reken ze niet twee keer.

`tvos-unified-experience.md` hoofdstuk 27 blijft de historische vastlegging van de fasen 0 tot en
met 10A; die fasen zijn gesloten en het hoofdstuk beschrijft geen open werk meer.

### Wat alleen op hardware kan

Vijf rijen uit het edge-caseregister die geen enkele test kan afsluiten: J2 4K-output,
J4 overscan, J8 VoiceOver, J9 Reduce Motion en I17 de Android TV-terugknop. Ze horen bij de
hardware-eindronde uit de closure. Zie [qa/tvos-unified-edge-cases.md](qa/tvos-unified-edge-cases.md).

`/pleya-tvbuild` zet een build van een gekozen SHA rechtstreeks op de gepairde Apple TV,
buiten App Store Connect om. Dat is de route naar dat bewijs, en de hardware-eindronde uit de
closure gebruikt hem voor de finale kandidaat.

---

## 7. Documenten die af zijn

Deze zijn geschiedenis. Ze blijven staan omdat ze het bewijs en de redenering dragen,
maar er staat geen werk meer in dat nog gedaan moet worden. Zoek de actuele stand in de
lijsten uit §3.

- `tvos-my-pleya-audit-2026-09-02.md`
- `tvos-my-pleya-styling-audit-2026-09-02.md`
- `tvos-my-pleya-styling-plan.md`
- `tvos-my-pleya-handoff-2026-09-02.md`
- `tvos-my-pleya-handoff-2026-09-03.md`
- `tvos-my-pleya-handoff-2026-09-03b.md`

Twee afwijkingsvoorstellen horen bij een fase die gesloten is en zijn daarmee ook
afgerond: `tvos-unified-fase6-home-rows-deviation.md` en
`tvos-unified-fase8-ambient-background-deviation.md`.

---

## 8. De volledige documentenkaart, tvOS en iOS

| Document | Rol | Levend |
|---|---|---|
| [unified-2026-closure.md](unified-2026-closure.md) | canonical werkvolgorde, statusladder, releasegate, hardware-eindronde en TestFlight-regel voor beide platforms | ja |
| [ios-unified-implementation-register.md](ios-unified-implementation-register.md) | de iOS-status per scherm | ja |
| [ios-unified-2026-audit.md](ios-unified-2026-audit.md) | de iOS-northstarautoriteit, tokens en beslispunten | bevroren |
| `ios-unified-2026-fase1-plan.md`, `-fase2-plan.md`, `-fase3-plan.md` | de gebouwde iOS-fasen 1 tot en met 3 | nee, historisch |
| [tvos-unified-experience.md](tvos-unified-experience.md) | architectuurbaseline, fasen, focuscontract, hoofdstuk 33 met de referentiemapping | ja |
| [tvos-netflix-ia-plan.md](tvos-netflix-ia-plan.md) | de IA- en UX-vertaling van de Netflix-referentie | ja |
| [tvos-redesign-implementatiecontract.md](tvos-redesign-implementatiecontract.md) | de vijftien productbesluiten onder mockup 09 tot en met 25 | ja |
| [tvos-redesign-09-25-approved.md](tvos-redesign-09-25-approved.md) | het approval-manifest met de hashes | ja |
| [tvos-redesign-register.md](tvos-redesign-register.md) | de voortgangsadministratie van dat bouwwerk | ja |
| [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md) | de masterlijst van alles wat op hardware gezien is | ja |
| [qa/tvos-unified-edge-cases.md](qa/tvos-unified-edge-cases.md) | het edge-caseregister van de fasen 0 tot en met 10A | ja |
| `assets/tvos-unified/approved-2026-09-03/01-code-parity-audit.md` | per mockup de bestaande code, met regelnummers | ja |
| de zes documenten uit §4 | sessiebewijs | nee |

---

## 9. Wat nog niet op één lijn staat, en het recept ervoor

### De DEC-nummers botsen op tien plekken

Gemeten over de vier lijnen: 109 nummers in omloop, waarvan **tien met tegenstrijdige
inhoud**. Dit is de grootste blokkade voor het samenbrengen, want `DECISIONS.md` is de
identiteitsregistratie waar de architectuurdocumenten, de registers en codecommentaar
naar wijzen.

| Nummer | main en web | iOS en ebooks |
|---|---|---|
| DEC-063 tot en met DEC-068 | de Unified TV-besluiten | de Pleya Verify-besluiten |

**Dat is geen echte botsing maar achterstand.** Main heeft dit zelf al opgelost: de zes
Verify-besluiten staan daar sinds de reconciliatie op **DEC-080 tot en met DEC-085**, en
de Unified TV-besluiten hebben 063 tot en met 068 gehouden. `feat/netflix-mobile` en
`feat/ebooks` dragen simpelweg de kopie van vóór die reconciliatie. Bij het landen nemen
ze main's versie over; er valt niets te hernummeren, alleen bij te trekken.

Wat wél een echte botsing is, want het zijn nieuwe besluiten op hetzelfde nummer:

| Nummer | Op main | Elders |
|---|---|---|
| DEC-091 | een TV-contentroute opent binnen de shell | iOS: de mobiele heropstelling heet `mobileFeatured` |
| DEC-092 | Bibliotheken wordt bronbeheer | iOS: fase 1 levert de iPhone-Home als eigen scherm |
| DEC-094 | de hero vraagt artwork in de bronratio aan | ebooks: mobiele vijfslots-navigatie |
| DEC-096 | taalvoorkeuren in vier lagen | web: refreshtokenrotatie met respijtvenster |

Vier hernoemingen dus, en main is de stam, dus die vier verschuiven aan de kant van de
branch. Main loopt tot 096 en heeft precies één gat, op **090**, dat door iOS' bevroren
northstarbesluit bezet is. Vanaf **097** is alles vrij.

**Bijgewerkt na de daadwerkelijke merge.** Niet `feat/netflix-mobile`, waar deze paragraaf
over gaat, maar `claude/ios-fase3-catalogus` is geland op
`integration/ios-unified-main-sync`. De twee delen hun geschiedenis tot en met fase 1 en
lopen daarna uiteen: beide bouwden fase 2 en fase 3 zelfstandig, met eigen DEC-nummers.
`feat/netflix-mobile` wordt niet gemerged, zie [DEC-106](DECISIONS.md#dec-106); Zoeken, wat
daar fase 4 is, komt terug als een eigen fase op de componenten die wel landen.

Main liep op het moment van de merge door tot **DEC-101**, met eigen inhoud onder 091, 092,
094 én 101 (een vierde botsing, ontstaan na fase 3, die deze paragraaf nog niet kende). Alle
vier zijn hernummerd naar **DEC-102 tot en met DEC-105**; DEC-090 bleef ongewijzigd, zoals
hierboven al vastgelegd. Zie [DEC-105](DECISIONS.md#dec-105) voor het volledige verslag van
de hernummering.

### De drie andere sets staan niet op `main`

iOS, Web en Ebooks leven elk op hun eigen branch. Zolang dat zo is kan niemand ze naast
elkaar leggen, en kan een besluit op het ene oppervlak ongemerkt in strijd zijn met het
andere. De goedkoopste stap is de assetmappen naar `main` te brengen zonder de
bijbehorende code: beelden zijn inert en conflicteren met niets. Niet gedaan, omdat het
een keuze van Michel is welke sets als richtinggevend de stam op mogen.

### De landingsvolgorde ligt vast door de sets zelf

Ebooks verklaart in zijn eigen manifest dat de iOS-set wint voor de uitvoering. **Ebooks
kan dus niet vóór iOS landen** zonder die afhankelijkheid om te draaien. De volgorde is:
tvOS staat er al, dan iOS, dan ebooks. Web staat daar los van en hangt aan de Pleya
Server-roadmap.

### Twee registers delen twee ID's

SYS-1 en SYS-4 staan in het redesign-register én in de correctieronde. De werkverdeling is
afgesproken, maar stond nergens als regel; §6 legt hem nu vast.

### De vijf losse `*-reference.png`

In de root van `assets/tvos-unified/` staat de voorloper van de northstar-set. Drie ervan
worden nergens meer genoemd. Ze zijn hier als historisch gemarkeerd en niet verwijderd,
want de repo verwijdert geen bewijs.
