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
| **iOS en mobiel** | `docs/assets/ios-unified/northstar/` | 21 schermen plus 5 comps | getekend, niet geland | alleen op de branch | `feat/netflix-mobile` |
| **Pleya Web** | `docs/assets/pleya-web-northstar/` | 46 schermen plus bron | getekend, niet geland | alleen op de branch | `integration/pleya-server-rebaseline` |
| **Ebooks** | `docs/assets/ebooks/northstar/` | 9 schermen plus bron | getekend, niet geland | alleen op de branch | `feat/ebooks` |

Alleen tvOS staat op `main`. De andere drie leven uitsluitend op hun eigen branch, en
dat is de spreiding die dit document zichtbaar maakt. Zie §6 voor wat daaraan te doen is.

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

## 3. Waar de volgende stap staat

Er zijn drie levende lijsten, en ze bezitten verschillende dingen. Dat is geen
duplicatie, maar het is wel makkelijk te verwarren.

| Lijst | Wat het bezit | Stand op 5 september |
|---|---|---|
| [tvos-redesign-register.md](tvos-redesign-register.md) | het bouwen van mockup 09 tot en met 25, plus de systemische eigenaren eronder | 61 rijen: 3 DONE, 1 IN PROGRESS, 54 OPEN |
| [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md) | alles wat op een echte Apple TV is gezien, en elk los verzoek van Michel | 68 rijen: 24 FIXED, 3 NOT REPRODUCED, 2 goedgekeurd met bouw open, 2 DEFERRED, 32 OPEN |
| [tvos-unified-experience.md](tvos-unified-experience.md) hoofdstuk 27 | de fasen 0 tot en met 10A en de afsluitende Final | 0 tot en met 10A gesloten, Final open |

**Twee rijen staan in allebei de eerste twee**: SYS-1 en SYS-4. Het register bezit ze als
werkitem, de correctieronde als hardwarebevinding. Dat is de afgesproken werkverdeling
en geen dubbeling, maar reken ze niet twee keer.

### De eerstvolgende stappen, in de volgorde die het register zelf voorschrijft

1. **SYS-1c** geneste routes krijgen de contentbox als `MediaQuery`. Staat op
   IN PROGRESS: gebouwd, nog niet bewezen.
2. **SYS-1b** film-, serie- en collectiedetail over hetzelfde geneste routecontract.
3. **SYS-3a** de schaalbasis van paneelinhoud op TV. SYS-3b is al DONE.
4. **De eerste echte Pleya Verify-journey**, over shell naar subpagina naar Back. Tot die
   er is geldt SYS-1 als implementation-proven en niet als end-to-end geaccepteerd.
5. Daarna BACK1, de gedeelde lege staat, i18n en tokens, en dan de mockups in blokken:
   09 tot en met 12, 13 tot en met 16, 17 tot en met 19, 20 tot en met 25.

### Wat alleen op hardware kan

Vijf rijen uit het edge-caseregister die geen enkele test kan afsluiten: J2 4K-output,
J4 overscan, J8 VoiceOver, J9 Reduce Motion en I17 de Android TV-terugknop. Ze horen bij
de Final-fase. Zie [qa/tvos-unified-edge-cases.md](qa/tvos-unified-edge-cases.md).

`/pleya-tvbuild` zet een build van een gekozen SHA rechtstreeks op de gepairde Apple TV,
buiten App Store Connect om. Dat is de route naar dat bewijs.

---

## 4. Documenten die af zijn

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

## 5. De volledige tvOS-documentenkaart

| Document | Rol | Levend |
|---|---|---|
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

## 6. Wat nog niet op één lijn staat

Drie dingen, met de reden waarom ze nog niet opgelost zijn.

**De drie andere northstar-sets staan niet op `main`.** iOS, Web en Ebooks leven elk op
hun eigen branch. Zolang dat zo is kan niemand ze naast elkaar leggen, en kan een besluit
op het ene oppervlak ongemerkt in strijd zijn met het andere. De goedkoopste stap is de
assetmappen naar `main` te brengen zonder de bijbehorende code, want beelden zijn
inert en conflicteren met niets. Dat is niet gedaan omdat het een keuze van Michel is
welke sets als richtinggevend de stam op mogen.

**Twee registers delen twee ID's.** SYS-1 en SYS-4 staan in het register én in de
correctieronde. De werkverdeling is afgesproken, maar staat nergens als regel; hier in
§3 staat hij nu.

**De vijf losse `*-reference.png` in de root van `assets/tvos-unified/`** zijn de
voorloper van de northstar-set. Drie ervan worden nergens meer genoemd. Ze zijn hier als
historisch gemarkeerd en niet verwijderd, want de repo verwijdert geen bewijs.
