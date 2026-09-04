# C. Northstar design review

Zelfreview van de kandidaatset, uitgevoerd op de gerenderde beelden (niet op de HTML), in twee
ronden op 4 september 2026. Elke bevinding noemt het beeld, wat er mis was, en of het is
gecorrigeerd in de set die nu in `docs/assets/pleya-web-northstar/` staat.

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
