# Mockup 38, Big P (Pleya Assistant), voorgesteld

| Veld | Waarde |
|------|--------|
| Status | PROPOSED DESIGN TARGET |
| Goedgekeurd door | nog niet; Michel Knoop beslist |
| Datum | 2 oktober 2026 |
| Set | 38 A tot en met I: hub-ingang, geen toegang, instellen (twee beelden), rust, luisteren, werken, resultaat, bevestiging (Pleya Server en Plex) |
| In de repo | `docs/assets/tvos-unified/mockups-2026-10-02-big-p/` |
| Bron | `docs/assets/tvos-unified/src/pages/38-big-p-*.html`, gedeelde opmaak in `src/assets/bigp/bigp.css` |
| Branch | `feat/pleya-assistant-core` |

Dit is een voordracht. Tot Michel akkoord geeft is geen enkel beeld een bouwopdracht. Bij akkoord
krijgt dit bestand de naam `tvos-redesign-38-big-p-approved.md`, status APPROVED en een DEC-nummer.

## Wat vaststaat en hier niet ter discussie ligt

Het product is besloten: Big P is een beheerassistent. De beheerder spreekt een verzoek in, een
taalmodel kiest Pleya-tools, Pleya controleert de rechten, vraagt bevestiging bij gevoelige acties,
voert uit en toont het resultaat. Big P legt uit en praat; Pleya beslist en handelt. De set tekent
dat na en ontwerpt het niet opnieuw.

Gevolgen die in elk beeld terugkomen:

- De enige ingang is een tegel in Mijn Pleya, groep Pleya. Geen zwevende knop, geen roottab, geen
  overlay op andere schermen, geen chatvenster.
- Big P heeft vier standen: rust, luisteren, werken, resultaat. Er beweegt niets behalve de focus.
- Ollama en OpenRouter staan alleen op het instelscherm (38 C2). Elders heet het "AI-provider".
- Een bevestiging is een kaart van Pleya met vaste velden, geen bericht van Big P. Big P staat er
  gedimd achter en heeft er geen tekst in.

## Standen en kunst

De kunst komt ongewijzigd uit `~/.claude/skills/big-p/avatar/`, verkleind naar 560x700 in
`src/assets/bigp/`. Ze staat alleen op donkere vlakken, want de bron heeft een donkere rand.

| Stand | Kunst | Waarom deze |
|-------|-------|-------------|
| Hub-tegel, geen toegang, instellen | `bigp-blij` | Neutraal vriendelijk. Een bezorgd gezicht bij "geen toegang" zou suggereren dat er iets stuk is, en dat is niet zo. |
| Rust (38 D) | `bigp-zwaaien` | De begroeting is de enige plek waar Big P iets "doet" zonder dat er een taak loopt. |
| Luisteren (38 E) | `bigp-verrast` | Open mond en grote ogen lezen op afstand als "ik let op". Kleiner getekend, zodat het toetsenbord ruimte heeft. |
| Werken (38 F) en achter de bevestiging (38 H, I) | `bigp-vinger_presenteren` | Een stilstaande houding die "momentje" zegt, zonder draaiend wiel of animatie. |
| Resultaat (38 G) | `bigp-duim_presenteren` | Duim omhoog plus een open hand naar de resultaatkaart: de figuur wijst naar wat Pleya deed. |

| Resultaat met fout (38 J) | `bigp-bezorgd` | Hoort bij de resultaatstand, niet bij een vijfde stand. De Pleya-kaart draagt de fout; Big P laat alleen zien dat het niet goed ging. |

## De beelden

| Nr | Bestand | Wat het beslist | Focus bij openen |
|----|---------|-----------------|------------------|
| 38 A | 38-big-p-a.png | Big P is een gewone hub-tegel, vooraan in de groep Pleya, met dezelfde maat, dichtheid en focusstijl als de andere tegels. In plaats van een lijnicoon draagt hij een klein portret van Big P rechts in de tegel. Ondertitel "Pleya Assistant". Uitloggen schuift naar een tweede rij onder de vouw. De rest van de hub volgt `buildTvMyPleyaGroups` en de Nederlandse teksten uit `nl.i18n.json`. | Big P-tegel (getekend als de gefocuste tegel; bij binnenkomst geldt de bestaande hubregel) |
| 38 B | 38-big-p-b.png | Beheerder zonder toegang. Big P staat er wel, met een korte uitleg en de zin dat je hem hier niet kunt aanzetten of kopen. Geen vraagknop, geen prijs, geen link naar een winkel. | "Terug naar Mijn Pleya", de enige knop |
| 38 C1 | 38-big-p-c1.png | Geen provider ingesteld. De letterlijke zin uit de opdracht als kop, één zin over wie wat doet, en "Big P instellen" als primaire actie. | "Big P instellen" |
| 38 C2 | 38-big-p-c2.png | Providerkeuze als drie gewone rijen: Ollama-server, Ollama Cloud, OpenRouter. Rechts staat wat je daarna nodig hebt (adres of API-sleutel). Onder de rijen staat welke gegevens naar de provider gaan en dat wachtwoorden en tokens in Pleya blijven. | Ollama-server, omdat dat de enige keuze is waarbij je vragen thuis blijven |
| 38 D | 38-big-p-d.png | Rust. Statusregel met de servers waarop Big P kan handelen, een begroeting, één primaire knop "Vraag Big P" en drie voorbeeldvragen als gewone focusbare knoppen. Een voorbeeld kiezen stuurt die vraag meteen. | "Vraag Big P" |
| 38 E | 38-big-p-e.png | Luisteren gebeurt in het systeemtoetsenbord van tvOS met dicteren, onderaan over het scherm. Pleya tekent geen eigen microfoonscherm. Big P staat kleiner in de luisterstand met "Ik luister…" en de kop "Spreek je vraag in.". | Bepaalt tvOS |
| 38 F | 38-big-p-f.png | Werken. De vraag staat er letterlijk boven, daaronder één statusregel "Bezig met je vraag…". Geen voortgangsbalk, geen tussenstappen. Annuleren is de enige knop. | "Annuleren" |
| 38 G | 38-big-p-g.png | Resultaat. Big P geeft een antwoord van één zin plus één zin uitleg. Daaronder staat een kaart van Pleya ("Uitgevoerd door Pleya · tijd") met per actie een regel: "Scan gestart · Films · Zolder". Daarna "Vraag Big P" en "Klaar". | "Vraag Big P" |
| 38 H | 38-big-p-h.png | Bevestiging, Pleya Server. Pleya-kaart "Gebruiker aanmaken" met gebruiker, server, toegang, "Beheerder: Nee" en een afgeschermd wachtwoordveld. Eén kaart voor het hele doel: aanmaken plus de toegang die erbij gevraagd is. Aanmaken is uitgeschakeld tot het wachtwoord is ingevuld. De kleine letters zeggen dat het wachtwoord niet naar Big P en niet naar de AI-provider gaat. | "Annuleren" |
| 38 I | 38-big-p-i.png | Dezelfde kaart voor Plex, met "Beheerder: Nee" en zonder wachtwoordveld: een beheerde Home-gebruiker heeft geen eigen login, en een pincode instellen zit niet in deze ronde. Aanmaken is meteen bruikbaar. De kleine letters zeggen wat er op Plex echt ontstaat: "Beheerde Plex Home-gebruiker, met een share op deze server." | "Annuleren" |
| 38 J | 38-big-p-j.png | Resultaat met fout, geen aparte stand: result(error). De bezorgde Big P, één zin over wat er misging en dat er niets veranderde, en een gewone Pleya-foutkaart: "Scan niet gestart · Films · Zolder" met een rode status. Daarna "Vraag Big P" en "Klaar". | "Vraag Big P" |

## Waarom Annuleren de standaardfocus is

Een bevestiging komt direct na het dicteren. De Select-druk waarmee je het toetsenbord afsluit
("Gereed") ligt dan nog in je duim, en op tvOS is een tweede druk zo gegeven. Staat de focus op
Aanmaken, dan maakt één onbedoelde druk een account aan dat je daarna moet opruimen. Staat hij op
Annuleren, dan kost diezelfde vergissing alleen het opnieuw stellen van de vraag. Aanmaken ligt één
stap naar rechts: dat is een bewuste handeling, en precies dat wil een gevoelige actie.

In 38 H is de volgorde in de praktijk: Annuleren (focus) of omhoog naar het wachtwoordveld,
wachtwoord invullen in het systeemtoetsenbord, terug naar rechts naar Aanmaken.

## Wat deze set niet beslist

- De functionele specificatie van tools, rechten of welke acties als gevoelig gelden. Het beeld
  toont één voorbeeld per soort.
- Hoe toegang (de entitlement) wordt vastgesteld en waar die vandaan komt.
- Of niet-beheerders de tegel zien. De voordracht gaat ervan uit dat de tegel voor hen ontbreekt,
  zoals Activiteit ontbreekt zonder bron. Getekend is alleen de beheerder.
- De invulschermen na 38 C2 (serveradres, API-sleutel, modelkeuze, verbindingstest).
- Foutstanden: provider onbereikbaar, geen rechten voor deze actie, actie mislukt.
- Een gesprek over meerdere beurten. De set gaat uit van één vraag, één uitkomst.
- iOS, iPad en desktop.
- De exacte vorm van het tvOS-toetsenbord. 38 E is een benadering; het echte toetsenbord tekent
  tvOS zelf, en de compositie geldt alleen voor wat Pleya eromheen tekent.

## Motion

De beelden hierboven blijven de autoriteit voor compositie. Dit hoofdstuk legt vast hoe Big P beweegt;
er komen geen extra beelden voor tussenstanden.

**Productregels.** Big P is rustig wanneer Pleya hem niet nodig heeft en komt tot leven wanneer de
gebruiker met de Assistant werkt. Motion ondersteunt status en persoonlijkheid en concurreert nooit
met de informatie of de beheeractie op het scherm.

**Techniek.** Flutter zelf: één `AnimationController` voor de doorlopende beweging, `Transform`,
`Opacity` en `AnimatedSwitcher` voor de rest. Geen Rive, Lottie, video of sprite-reeks. Alleen de
avatar rebuildt, niet het scherm eromheen (eigen `RepaintBoundary`).

**Lagen**, uit `~/.claude/skills/big-p/avatar/lagen/` en verkleind naar de helft:

| Laag | Bron | Beweegt |
|------|------|---------|
| Lichaam | `body.png` (rusthouding, zonder wenkbrauwen) | ademen, kantelen rond de voeten, knik |
| Mond | `mouth-rest`, `mouth-small`, `mouth-laugh`, `mouth-o` op het mondvak uit `bigp-layers.json` | wisselt per stand; dezelfde plek waar later lipsync kan landen |
| Wenkbrauwen | `brow-l.png`, `brow-r.png` | optillen en kantelen |
| Oogleden | getekend met een `CustomPainter` op de oogmaten en lidkleuren uit `bigp-layers.json` | knipperen |

Er is geen pupillaag. De blik wordt een kanteling van de hele figuur; een losse pupil is pas nodig als
dat te weinig blijkt. De bezorgde Big P is dezelfde laag-opbouw met andere wenkbrauwen en mond, geen
losse afbeelding, zodat de figuur niet verspringt.

**Per plek en stand**

| Waar / stand | Houding en expressie | Wat beweegt | Naar de volgende stand |
|------|------|------|------|
| Hub-tegel, rust | stil portret, `mouth-rest` | niets | bij focus één reactie |
| Hub-tegel, focus | wenkbrauwen even omhoog, figuur tilt 4 px | één keer, 400 ms, geen herhaling | terug naar stil |
| idle | ontspannen, `mouth-rest`, wenkbrauwen neutraal | ademen (schaal 1,000 tot 1,012 in 4 s), knipperen om de 3 tot 6 s, af en toe een kanteling van 1,5 graad die even blijft staan | naar listening: wenkbrauwen omhoog en rechtop, 250 ms |
| listening | aandacht naar de kijker: rechtop, wenkbrauwen omhoog, `mouth-small` | ademen trager, minder knipperen, een kleine knik als er gedicteerde tekst binnenkomt (hoogstens één per seconde) | naar working: kantelt richting het resultaatvlak, 300 ms |
| working | denkt na: 3 graden gekanteld naar rechts, wenkbrauwen licht scheef, `mouth-rest` | ademen, langzaam heen en weer kantelen tussen 2 en 4 graden zolang de run loopt | naar result: korte reactie |
| result (succes) | `mouth-laugh`, wenkbrauwen omhoog | één knik van 600 ms | na de knik terug naar idle-beweging met `mouth-rest` |
| result (fout) | bezorgd: wenkbrauwen naar binnen omhoog, `mouth-small` | één kleine zak van het hele figuur, dan stil buiten het knipperen | blijft bezorgd zolang de foutkaart staat; terug naar idle bij een nieuwe vraag |

De statusregel naast Big P zegt wat er gebeurt ("Even kijken…", "Jellyfin controleren…",
"Bibliotheek scannen…"). Er komt geen spinner en geen golfvorm om de figuur.

**Minder beweging.** Staat de systeeminstelling voor minder beweging aan
(`MediaQuery.disableAnimations`), dan is er geen doorlopende beweging: geen ademen, knipperen of
kantelen. Standen wisselen alleen mond en wenkbrauwen, met een korte opacity-overgang.

**Geen lipsync** in deze ronde. De mondlaag is wel een losse laag, zodat een gesproken antwoord hem
later kan aansturen.

## Oproepen vanaf elk scherm

Bijgesteld door Michel op 2 oktober 2026, na de eerste ronde beelden.

- Een lange druk op Play/Pause (minstens 600 ms) roept Big P op vanaf elk scherm buiten de speler.
  Tijdens playback blijft Play/Pause gewoon afspelen en pauzeren.
- Big P verschijnt zwevend rechtsonder, levend volgens de motion-spec, met een compact paneel en het
  systeemtoetsenbord met dicteren al open. Het scherm erachter dimt licht en blijft de context:
  "Scan deze bibliotheek opnieuw" op de Films-catalogus betekent die bibliotheek.
- Werken en resultaat staan in het compacte paneel. Na het resultaat schuift Big P weer weg. Een
  gevoelige actie toont dezelfde Pleya-bevestigingskaart, gecentreerd, en Big P blijft tot die is
  afgehandeld.
- Big P staat niet permanent in beeld. Alleen beheerders kunnen hem oproepen.
- Techniek: tvOS stuurt Play/Pause nu al bij het indrukken door; er komt een bericht bij het
  loslaten bij, zodat de duur buiten de speler gemeten kan worden. De Siri-knop zelf is van tvOS en
  wordt niet gebruikt. Op echte hardware te bewijzen.

## Besluiten van Michel, 2 oktober 2026

1. De tegel staat vooraan in de groep Pleya: Big P, Instellingen, Logs en diagnose, Over, Uitloggen.
2. De tegel draagt het portret van Big P, geen lijnicoon, maar blijft een gewone hub-tegel. Geen
   afwijkende advertentiekaart.
3. De primaire knop heet "Vraag Big P". Hij beschrijft de actie en niet het invoermiddel; typen via
   het systeemtoetsenbord of een iPhone kan ook. Tijdens luisteren staat er "Ik luister…".
4. Geen vijfde stand. Een mislukking is de resultaatstand met fout (38 J): bezorgde Big P plus een
   gewone Pleya-foutkaart.
5. Eén logisch doel is één bevestiging. "Maak Sam aan en geef hem alleen toegang tot Kids" is één
   kaart (38 H, 38 I) met de toegang erin; Pleya voert de stappen daarna na elkaar uit en meldt
   eerlijk welk deel mislukte. Twee losse gevoelige acties blijven twee kaarten. Er komt geen
   algemene bundel- of transactielaag.

## Nog open

1. **Voorbeeldvragen.** Voorstel: een vast drietal in deze ronde. Kiezen op basis van wat er op de
   servers speelt kan later zonder ander ontwerp.
2. **Annuleren tijdens werken (38 F).** In de core stopt Annuleren het wachten op het model; een
   actie die Pleya al heeft uitgevoerd wordt niet teruggedraaid, en een gevoelige actie loopt nooit
   zonder kaart. De knop blijft daarom staan, en de resultaatkaart toont wat er al gebeurd was.

## De beelden, hashes

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 38 A | 38-big-p-a.png | `faf2f99fa862663f7a6ee7fff84769abc6008fc7ebea4607a00bce2e9568e024` |
| 38 B | 38-big-p-b.png | `4d75b1277c8bd91fbcbe8d201bf5934dd8e7522ee6eb0eb9b59e0cab893432ac` |
| 38 C1 | 38-big-p-c1.png | `47bcea3eb61579e24a0e8be8e68d519106e8a7a7cb213584c8043a108b57a427` |
| 38 C2 | 38-big-p-c2.png | `da775770dbebee4afa112107cecd587dd121fdda0840ecc6872362faf9a23964` |
| 38 D | 38-big-p-d.png | `dcdc7db885c71248dbe60406a2e378d2d6278593e2b0ca2dbc6363d0f8053475` |
| 38 E | 38-big-p-e.png | `d5394f64509ffd5de4edf6bd68d4f2489918872f118979dddc5540551b159c4c` |
| 38 F | 38-big-p-f.png | `c51f2ccb5d2f8791022249c292b1ec30d55deedec60a16ee32de3975d3fbc17d` |
| 38 G | 38-big-p-g.png | `4a66b95debe58ff9a9c7d1accf86b637fc42e0001e2ad4eb8575d7c46a9a5a61` |
| 38 H | 38-big-p-h.png | `4287a7fbf5f74bc5b24fdae3694fe720c192589fa6b0f1d5851b2d5e1270368b` |
| 38 I | 38-big-p-i.png | `6c6b732261c340e5a6b083ea6d3e1148f93fd9aee1f6dc4e8c932935f5bdb47a` |
| 38 J | 38-big-p-j.png | `c8c345b52b093794ee004e4b692de3737c7465f70d5eb07dcb8830013db979a5` |

Herschieten: `cd docs/assets/tvos-unified/src && PLEYA_MOCKUP_DEST=$PWD/../mockups-2026-10-02-big-p node build.mjs 38-big-p`.
Een andere pixel betekent een andere hash; werk dan deze tabel bij.

## Wanneer er opnieuw akkoord nodig is

Dezelfde vier gevallen als bij 09 tot en met 37: een andere compositie dan het beeld tekent, een
componentfamilie die niet in de set voorkomt, een dichtheid die van de getekende afwijkt, en een
gedragswijziging die het beeld niet kan tonen maar die een eerder productbesluit raakt. Voor Big P
komt daar een vijfde bij: elke plek buiten Mijn Pleya waar Big P zichtbaar wordt.

## Motion, tweede ronde (2 oktober)

Michels oordeel over de eerste ronde: "Big P is nog steeds te statisch." Deze sectie vervangt de
tabel "Per plek en stand" uit het hoofdstuk Motion. De productregel blijft: Big P bedekt geen
informatie en concurreert niet met de beheeractie. Het prototype staat in
`docs/assets/tvos-unified/src/prototype/38-big-p-motion/` met de getallen in de README; de stills in
`mockups-2026-10-02-big-p/motion/` (`38-motion-0` tot en met `38-motion-7`).

**Altijd, buiten minder beweging.** Big P zweeft een paar pixels boven de vloer (schaduw krimpt mee),
wiegt rond zijn voeten, ademt en kantelt om de paar seconden zijn hoofd. Hij knippert om de 2 tot 4 s,
soms twee keer snel achter elkaar. Overgangen lopen via een veer die een fractie doorschiet. Bij
binnenkomst, aan het begin van een scherm en bij succes maakt hij een sprong met inveren, strekken en
landen; weggaan is een sprongetje richting de uitgang.

**Houdingen en armen.** Lagen uit de big-p-skill: zwaaien met een draaiende arm, wijzen met een losse
arm achter het lichaam (bereik -12 tot 60 graden), vinger omhoog, duim omhoog, juichen. Een wissel
duurt 270 ms en springt halverwege om terwijl het lichaam inveert, zonder overvloeien.

**Praten.** Zijn antwoord verschijnt woord voor woord en de mond loopt mee op het ritme van de
lettergrepen (zeven mondstanden, dicht tussen zinnen). Op lange woorden, namen en cijfers knikt het
lijf en gaan de wenkbrauwen omhoog. Geen stem, geen lipsync-engine.

| Stand | Wat Big P doet |
|------|------|
| rust | levende lus, om de 6 tot 11 s even kijken naar de voorbeeldvragen, om de 15 tot 25 s zwaaien |
| luisteren | zakt iets in naar het toetsenbord, wenkbrauwen omhoog, ronde mond, hoofd scheef dat van kant wisselt, knikje per binnenkomend woord |
| werken | wijst de nieuwste stap aan en volgt de lijst, hoofd draait mee bij elke stap, denkende wenkbrauwen, vinger omhoog als een stap klaar is |
| succes | juicht met een sprong, zegt het antwoord met een duim omhoog, komt tot rust |
| fout | hoofdschudden, zakt door, bezorgde wenkbrauwen; zegt de foutmelding rustig, zonder nadruk |
| bevestigingskaart | stapt opzij, kijkt naar de kaart, zweeft weinig, knikt als je bevestigt |
| opgeroepen | dezelfde figuur kleiner in de hoek, met sprong erin en eruit, kijkrichting naar het paneel links |

**Minder beweging.** Geen lussen, sprongen of knikken. Alleen houding, wenkbrauwen en mond wisselen,
direct. Tijdens praten staat de mond half open.

**Paneel.** Het gesprek staat niet meer over de volle breedte. Op de Big P-plek ligt een zwevend
glaspaneel van 800 px (ongeveer 42 procent van 1920) rechts van een grotere Big P, onderaan
verankerd zodat het nieuwste onderaan staat; antwoordregels komen uit op 45 tot 55 tekens. De vraag
van de gebruiker staat als korte geciteerde regel boven het antwoord, stappen, resultaat- en
keuzekaarten en voorbeeldvragen passen binnen het paneel. Het Pleya-scherm blijft vervaagd en gedimd
zichtbaar eronder. Het glas is het tvOS-nepglas van LG-04 tot en met LG-06; kaarten op het glas houden
een donkere ondergrond voor contrast, de focusring blijft wit. Bevestigingskaarten blijven
ondoorzichtige Pleya-kaarten midden in beeld, 880 px breed. Opgeroepen is het paneel 570 px.

**Nieuw: aanvragen op beschrijving** (scene 7). De gebruiker beschrijft een film in plaats van de
titel. Big P bedenkt titels en doorzoekt Seerr, toont vier keuzekaarten in het paneel (poster, titel,
jaar, één regel beschrijving, status Aan te vragen, Beschikbaar of Al aangevraagd) en wijst de kaart
met focus aan. Kiezen opent direct de Pleya-kaart om aan te vragen, met focus op Annuleren.

**Grenzen.** Geen pupillen, dus kijken blijft een kanteling. De mondsprites komen uit lachende
mockups; bezorgd gebruikt de ronde mond. De driekwart-wijshouding van de opgeroepen Big P heeft een
eigen gezicht, dus daarin knippert hij niet. Getest in Chromium, niet in Safari of op een Apple TV.
