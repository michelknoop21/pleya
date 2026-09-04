# C. Northstar design review

Zelfreview van de kandidaatset, uitgevoerd op de gerenderde beelden (niet op de HTML), in drie
ronden op 4 september 2026. Elke bevinding noemt het beeld, wat er mis was, en of het is
gecorrigeerd in de set die nu in `docs/assets/pleya-web-northstar/` staat.

Ronde 1 en 2 dekten de veertig schermen van de eerste kandidaatset (C.2, bevindingen 1 tot 12).
**Ronde 3** dekt de vijf schermen die na de scopebesluiten van 4 september bij kwamen (17, 18,
19, 28 en 35) en staat in C.5. Drie bevindingen daaruit zaten in `web.css` en raakten elk beeld;
de hele set is daarom opnieuw gerenderd. **Ronde 4** dekt de zes schermen die er als laatste bij
kwamen (11b, 36, 37, 38, 50 en 51) en staat in C.7. Daarmee is de set 46 schermen en ontbreekt er
niets meer.

## C.1 Toetsing per criterium

| Criterium | Toets | Uitkomst |
| --- | --- | --- |
| 1. iOS-northstars (DEC-090) | 01@393 naast `home-comp`; 08@393 naast `06-film-detail`; 09@393 naast `07-serie-afleveringen`; 10@393 naast e-books golden 05 | hero-kaart, tabbalk, kop, detailvoorvertoning, capsuleknoppen en de metaregel volgen de set; afwijkingen: `Meer info` in plaats van `+ Mijn lijst` (bewust, RB-2), segmentindicator in plaats van dots (bewust) |
| 2. Tokens en componenten | `web.css` regel voor regel tegen `tokens.css` en `tv.css` | geen kleur buiten het palet; radii 8/12/14/18; capsuleknop is een bewuste wijziging op `base.css` (radius 4) |
| 3. E-books-IA | 04 en 10 tegen paneel 1 en 5 van de comp en golden 01b en 05 | Verder lezen liggend met cover rechts en ambience, `48% · Hoofdstuk 12`, `Alle boeken ›`, detail met reeks en feiten: conform; op web staat de cover links van de tekst op breed (nieuw, want de comp is alleen mobiel) |
| 4. Servercapaciteit | elke knop in D.3 en D.4 heeft een bestaand of gepland endpoint | geen knop zonder endpoint; wat de server niet doet staat als tekst ("niet in deze versie") en niet als grijze knop |
| 5. Responsief | 01 en 04 op vier breedtes; 20 op drie; alle overige op 1600 en 393 | geen horizontale overloop van de pagina na ronde 2; tabellen scrollen in hun paneel |
| 6. Toegankelijkheid | contrast van `--ink-3` op `--surface` (4,6:1), focusring 3 px wit, raakvlakken ≥ 44 px, hover apart van focus | in orde; de echte axe-run hoort bij S7 |
| 7. Beheer versus consumer | 20 tot 34 naast 01 tot 16 | zelfde tokens en shell; beheer onderscheidt zich door zijbalk, tabellen, dichtheid en de amber Beheer-pil, niet door een tweede schema |
| 8. Visuele consistentie | dezelfde fixturegetallen op elk beheerscherm; dezelfde vijf titels in Verder kijken op 01, 02 en 16 | consistent |

## C.2 Bevindingen en correcties

| # | Beeld | Bevinding | Correctie |
| --- | --- | --- | --- |
| 1 | alle | wordmark en avatar laadden niet (pad relatief aan `out/`) | `../assets/` in de shell |
| 2 | alle @393 | tabbalk stond midden in een fullPage-shot | telefoonbeelden zijn één schermvulling, zoals de iOS-set |
| 3 | 05@1600 | letterlijke `}}` op de pagina door een geneste `{{icon}}` in de shell-opties | `navAction=naam` in plaats van een genest token |
| 4 | 05, 16 | hover- en focusstaat onzichtbaar (kaartopties werden niet geparsed) | eigen parser voor kaartopties met komma's |
| 5 | 20, 22 | Beheer-item in de topnav was een leeg wit blok (icoon wit op wit) | amber pil met icoon en label "Beheer", ambergevuld wanneer actief |
| 6 | 22, 27 | vinkjes in aangevinkte checkboxes onzichtbaar (`.row .ic` overschreef de kleur) | specifiekere regel voor `.checkbox .ic` |
| 7 | 24@393 | knop in de waarschuwing overlapte de tekst | waarschuwing wikkelt op smal, knop op een eigen regel |
| 8 | 09@393 | iconknoppen (gezien, meer) werden elk een rij van volle breedte | primaire en secundaire knop vol breed, iconknoppen op één rij |
| 9 | 27@393 | paneel met tabel duwde de pagina breder dan de viewport | gridcellen `min-width: 0`, tabel scrolt in het paneel |
| 10 | 10@1600 | "Meer van Frank Herbert" herhaalde de reeksrij | vervangen door "Ook in Sciencefiction" |
| 11 | 02@1024, 04@1024 | topnav krap: zoekveld en cluster raakten elkaar | smaller zoekveld en kleinere itempadding onder 1200 |
| 12 | 24, 25 | gedachtestreepjes als lege waarde in tabellen (anti-slop-hook) | "onbekend" en "n.v.t." |

## C.3 Wat de review niet kon toetsen

De echte renderprestaties (skelet naar inhoud), toetsenbordnavigatie in een echte browser,
axe, en `prefers-reduced-motion`: die horen bij S7 met de e2e-tests. De speler en de reader
hebben geen beeld (D.5). Live-vergelijking tegen de draaiende app was niet mogelijk zonder de
`main`-shell op deze branch; de vergelijking is gedaan tegen de goedgekeurde PNG's.

## C.4 Open voor goedkeuring

1. De set als geheel (RB-2).
2. `Meer info` en de segmentindicator als web-invulling van DEC-090 paragraaf 10.
3. Boeken zichtbaar op web (RB-3).
4. De beheerindeling in tien secties plus Agents (scherm 34).
5. De scope-grens (RB-18).

## C.5 Ronde 3: de vijf schermen van de uitgebreide scope

Getoetst op dezelfde acht punten uit `DESIGN.md` hoofdstuk 6, plus de bindende antwoorden uit
`VRAGENLIJST.md` hoofdstuk 8 die deze schermen dragen (31, 32, 37, 39, 40, 54, 55).

| # | Beeld | Bevinding | Correctie |
| --- | --- | --- | --- |
| 13 | 28@1600 | de note viel over het laatste paneel en was daar onleesbaar; hij hing `position: fixed` in de viewport terwijl het beeld een fullPage-shot is | `.note` staat nu in de flow aan het eind van het document; raakt elk breed beeld |
| 14 | 17@393, 05@393 | het raster liep buiten de viewport en toonde twee kolommen waar er drie horen; een kaarttitel met `white-space: nowrap` bepaalde de minimale trackbreedte | `.grid .card { min-width: 0 }`; hiermee klopt punt 2 van de reviewlijst ook op 05, dat in ronde 2 ten onrechte schoon werd verklaard |
| 15 | 17@1600, 17@393 | het vierluik zat als inline layout in de pagina en schaalde niet mee | `.quad` en `.grid.quads` in `web.css`; twee kolommen onder 900 |
| 16 | 17@393 | de "+" in de mobiele kop en de knop "Nieuwe verzameling" waren dezelfde actie | de kop houdt alleen terug en titel; de knop met het werkwoord blijft |
| 17 | 17@1600 | segment en sortering stonden in één chipsrij, waardoor een filter en een sortering hetzelfde leken | `.bar-row`: segment links, sortering rechts, op smal eronder |
| 18 | 18@1600, 18@393 | het vinkje "gezien" was een wit vlak: `.row .ic` overschreef `.seen .ic` in kleur en maat, dezelfde botsing als bevinding 6 | eigen regel `.row .seen .ic` |
| 19 | 18@1600 | de kop zei 11u 42m, de zes rijen tellen op tot 10u 45m | speelduur gecorrigeerd |
| 20 | 18@393 | de drie knoppen stonden als smalle kolom rechts naast een omgebroken titel | primaire en secundaire knop vol breed, iconknop op een eigen regel, gelijk aan bevinding 8 |
| 21 | 19@1600 | waarderingen stonden als duim omhoog of omlaag, terwijl vraag 32 numeriek 1 tot 10 vastlegt | cijfer per titel, met de providerscore ernaast en een regel die het verschil uitlegt |
| 22 | 19@1600 | vraag 31 geeft de gebruiker het recht zijn geschiedenis te wissen; er was geen enkele knop voor | "Geschiedenis wissen" naast de paginatitel |
| 23 | 19@1600 | de favorietenrail werd hard afgeknipt op de paneelrand, zonder de fade die een rail elders wel heeft | `.panel .fade-r` |
| 24 | 19@393 | de chipsrij stond naast de paginatitel en duwde Series en Boeken buiten beeld | chips naar een eigen `.bar-row` onder de titel |
| 25 | 28@1600 | alleen VAAPI stond er; vraag 37 maakt VAAPI, QSV en NVENC alle drie first-class met runtime-detectie | vier regels met de gedetecteerde staat per backend en software als terugval |
| 26 | 28@1600 | "oudste sessie eerst weg" botst met vraag 39, die actieve sessies juist beschermt | tekst herschreven; het quotum staat er als instelling, niet als constante |
| 27 | 28@1600 | het ondertitelbeleid uit vraag 40 stond nergens | eigen veld: bitmap en niet-converteerbare ASS inbranden, tekst als WebVTT |
| 28 | 28@1600 | de rechterkolom was twee panelen langer dan de linker | "Beheerd door de omgeving" naar links |
| 29 | 35@1600 | schema 13, terwijl dit scherm bij S25 en migratie `0019` hoort | schema 19 in beide panelen |
| 30 | 35@1600 | doel, tijdstip en retentie stonden als vaste tekst; vraag 54 maakt ze instellingen en vraagt een waarschuwing als het doel op hetzelfde failure-domain staat | instellingenlink in de paneelkop plus de waarschuwing als `alert` |
| 31 | 35@1600 | de hersteltest "telt de titels na"; vraag 54 vraagt migraties, schema en kernqueries in een geisoleerde database | tekst herschreven |
| 32 | 35@1600 | onderhoudsmodus stond in rood, de kleur van een fout; het is een waarschuwing | amber, met de formulering uit vraag 55 |
| 33 | 35@393 | de tabel scrolde horizontaal, waardoor "Terugzetten" per rij buiten beeld viel | `.table.stack`: onder 900 wordt een tabel met een actie per rij een lijst |
| 34 | 35@1600 | drie van de vier faalpaden werden afgekapt in hun smalle paneel | teksten ingekort |

Wat de review niet vond en dus staat: de fixture van 17 toont vier verzamelingen naast elkaar op
1600, waardoor de rechterhelft van het raster leeg blijft. Dat is de dichtheid van een huishouden
met vier verzamelingen en geen layoutfout; de aantallen liggen bij goedkeuring niet vast.

## C.6 Wat ronde 3 aan de hele set veranderde

Drie correcties zaten in `web.css` en raken elk beeld: de note in de flow (13), `min-width: 0`
op een rasterkaart (14) en de stapelende tabel (33). Alle 40 schermen zijn daarna opnieuw
gerenderd, dus elk beeld komt uit dezelfde bron en dezelfde CSS. Bevinding 14 corrigeert een
uitspraak uit C.1 criterium 5: 05@393 liep wel degelijk buiten de viewport en dat is in ronde 2
gemist.

## C.7 Ronde 4: de zes laatste schermen

Dezelfde acht punten, plus de vragen die deze schermen dragen (15, 16, 26, 32, 37, 39, 40, 42,
43, 53). De speler en de reader zijn de eerste twee schermen in de set zonder paginashell: ze
hebben geen topnav, geen tabbalk en geen inset, want ze zijn zelf de laag waarin je zit.

| # | Beeld | Bevinding | Correctie |
| --- | --- | --- | --- |
| 35 | 36@1600 | de veldenlijst stond in de smalle kolom met een vaste labelbreedte van 140 px, waardoor elke waarde afkapte ("Paul At…") en de herkomst over vier regels brak | `.fld` herzien: label, bron en actie op regel 1, waarde en herkomst op regel 2, zonder afkappen |
| 36 | 50@1600 | de kleine transportknop stond op afspelen terwijl de grote knop op pauze stond | beide op pauze |
| 37 | 50@393 | de titel brak over de terugknop heen en de codectags duwden de balk uit beeld; rechtsonder vielen twee bedieningen buiten de viewport | `.wide-only`: wat op een telefoon niet past staat er niet, in plaats van half |
| 38 | 50@393 | de titel stond wit op een lichte kap, want de scrim liep bovenaan tot 62 procent zwart | scrim naar 78 procent, punt 5 van de reviewlijst |
| 39 | 51@393 | de kop was 56 px hoog en de ondertitel brak over drie regels; de boektitel viel er helemaal uit, en de voortgangsbalk en het instellingenvel stonden onder de vouw | vier iconknoppen terug naar twee, en op smal toont het blad precies één pagina in plaats van door te lopen |
| 40 | 51@1600 | het instellingenvel zei "Sepia" terwijl het blad donker rendert | label klopt nu met wat je ziet; sepia en licht staan er als keuze naast |

Wat bij het tekenen zelf opviel en meteen goed is gezet, zonder eerst fout te renderen: de
speler noemt "Direct play · HEVC 4K" als tag, zodat het scherm eerlijk is over wat de server op
dat moment doet (en dus ook kan zeggen dat hij transcodeert); 37 toont "trager dan realtime" als
eigen signaal, want dat is het moment waarop een kijker gaat bufferen; en 38 heeft bewust geen
knop om een client te ontkoppelen, omdat een sessie intrekken in Beveiliging hoort en de
websocket dan vanzelf sluit.

## C.8 Wat de vier ronden samen opleveren

46 schermen uit 46 HTML-bronnen, één CSS, één renderer. Elk beeld in
`docs/assets/pleya-web-northstar/` is met dezelfde `web.css` gemaakt als elk ander beeld. De
reviewlijst uit `DESIGN.md` hoofdstuk 6 is op alle 46 gelopen; wat er niet mee te toetsen was
(echte renderprestaties, toetsenbordnavigatie in een browser, axe, `prefers-reduced-motion`)
staat in C.3 en hoort bij S7.
