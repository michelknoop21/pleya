# Roadmap deviation proposal — hoofdstuk 9.3 "Ambient background" uit fase 8


> **Afgehandeld afwijkingsvoorstel.** De fase die dit voorstel betrof is gesloten en het
> besluit is doorgevoerd; de statusregel bovenaan zegt hoe. Dit bestand blijft staan als
> de vastlegging van die afwijking. Welke beeldenset vandaag bindt en wat de
> eerstvolgende stap is, staat in [DESIGN-INDEX.md](DESIGN-INDEX.md).

**Datum:** 31 augustus 2026
**Fase:** 8 (Final TV Home Experience)
**Status:** goedgekeurd door Michel, 1 september 2026 — **doorgevoerd**: hoofdstuk 9.3's ambient tint en `tv_ambient_background.dart` staan vanaf nu in fase 9, hoofdstuk 9.3 zelf ongewijzigd
**Vorm:** de zes onderdelen uit hoofdstuk 23.1 van `docs/pleya-server-architecture.md`

Aanleiding: de onafhankelijke read-only systeemaudit op de volledige fase-8-diff stelde vast dat
`lib/widgets/tv/tv_ambient_background.dart` in hoofdstuk 27's **Toevoegen**-lijst voor fase 8 staat,
niet bestaat, en nergens als uitgesteld geregistreerd is. Dat laatste is het echte probleem. Een
niet-geleverd onderdeel is een planningsvraag; een stilzwijgend niet-geleverd onderdeel is
roadmapdrift, en hoofdstuk 23.1 en CLAUDE.md's punt 5 vragen er allebei expliciet om dat een afwijking
eerst als voorstel op tafel komt in plaats van vanzelf te gebeuren.

---

## 1. De oorspronkelijke aanname

Hoofdstuk 9.3 beschrijft een ambient achtergrond: "Buiten de hero komt een subtiele donkere
kleurtint uit het actieve artwork: decodeer een miniatuur van ongeveer 32×18; bepaal een gedempte
dominante kleur; cache op artwork-key; meng op lage alpha met de achtergrond; geen live
fullscreen-blur; op reduced-performance-tier een vaste themagradient." Hoofdstuk 27 zet
`tv_ambient_background.dart` daarom in de fase-8-toevoeglijst.

De aanname was dat de tint bij de nieuwe compositie hoort: een hero die niet langer full-bleed is
laat paginagrond over, en die grond zou de kleur van de actieve slide moeten oppikken.

## 2. De nieuwe bevinding

De tint is een **eigen subsysteem**, geen presentatiedetail van de kaart. Hij vraagt om: een
pixelpad dat er nu niet is (`ImageStream` → `ui.Image` → `toByteData` → gedempte dominante kleur),
een cache op artwork-key met een levensduur, een performance-tier-tak, en een animatie die meeloopt
met de 460 ms crossfade van de carousel zonder er tegenin te werken. Niets daarvan bestaat al: de
app heeft geen dominante-kleurextractie, en `OptimizedMediaImage` levert een widget, geen bitmap.

Twee dingen volgen daaruit, en beide zijn waar:

1. **Het is niet geleverd.** De pagina achter de hero is `scaffoldBackgroundColor`, vlak; de enige
   niet-token-verf buiten de kaart is de `ShaderMask`-fade onderaan de feed.
2. **Het is niet visueel te accepteren in deze fase.** De bindende north star (33.1, `01-home.jpg`)
   toont een vlakke `#141414`-grond rond de kaart. De tint is dus per definitie niet af te lezen
   tegen het beeld waaraan fase 8 wordt geaccepteerd — hij zou als enige onderdeel van deze fase op
   niets dan de tekst van 9.3 gebouwd en op niets dan een eigen oordeel goedgekeurd worden.

## 3. Waarom de roadmap daardoor niet meer klopt

Fase 8's Definition of Done noemt de ambient background niet. Hoofdstuk 27's **Toevoegen**-lijst
wel. De fase kan dus tegelijk "done" en "niet compleet" zijn, en dat is precies de dubbelzinnigheid
die hoofdstuk 23.1 wil voorkomen — te meer omdat de fase-8-closure inmiddels "alle punten hierboven
zijn geleverd en bewezen" claimt.

Wat niet klopt is dus niet de *eis* — 9.3 blijft een productvereiste — maar de fase waarin hij staat,
en de closure die hem meetelt zonder hem te leveren.

## 4. De concrete voorgestelde wijziging

1. `lib/widgets/tv/tv_ambient_background.dart` en hoofdstuk 9.3's ambient tint verhuizen van fase 8
   naar **fase 9** (functionele integratie en uitzonderingen), waar de performance-tier-tak en de
   cachelevensduur naast de andere runtime-gedragingen beoordeeld kunnen worden.
2. Hoofdstuk 27's fase-8-**Toevoegen**-lijst verliest het bestand; fase 9 krijgt het erbij, met 9.3
   bij naam.
3. De fase-8-closure wordt beperkt tot wat hij bewijst, en noemt deze afwijking.
4. Hoofdstuk 9.3 blijft **ongewijzigd**. De eis wordt niet versimpeld en niet geschrapt; alleen zijn
   fase verschuift.

## 5. De gevolgen voor latere fasen

Fase 9 wordt één zelfstandig onderdeel groter, en op een voorspelbare manier: het raakt niets van wat
fase 8 heeft gebouwd behalve de kleur van de paginagrond, en `TvContentFeed` heeft daar precies één
plek voor (de `Material` waarin de feed hangt). Er is geen migratie en geen herbouw voor nodig.

Tot dan blijft één zichtbaar verschil met hoofdstuk 9.3 staan: de grond rond de hero is vlak in
plaats van licht getint naar het actieve artwork. Dat is wat de bindende north star óók toont, dus
het is geen zichtbare fout tegen het beeld waartegen fase 8 geaccepteerd wordt — maar het is nu wél
een geregistreerde uitzondering met een datum eronder in plaats van een gat.

## 6. Welke scope hierdoor juist vervalt

Uit fase 8 vervalt: het bouwen van een dominante-kleurextractie, zijn cache, zijn performance-tier-tak
en de bijbehorende tests. Dat is geen uitgestelde klus die ergens blijft hangen — het is werk dat in
fase 8 zonder acceptatiebeeld gedaan zou worden en in fase 9 alsnog tegen de runtime-tier beoordeeld
moet worden.

Wat **niet** vervalt is de eis zelf. Hij is verplaatst, niet geschrapt, en hoofdstuk 23.1's tweede
helft is hier expliciet van toepassing: een latere productvereiste mag niet versimpeld worden omdat
de huidige fase hem niet nodig heeft.

---

## Roadmap Drift Check (fase 8)

- **Is er iets gebouwd dat niet in de scope stond?** Ja, drie dingen, alle drie vastgelegd in
  [DEC-070](DECISIONS.md#dec-070): de uitvoering van hoofdstuk 9.6's pauzecontract (punt 1), het
  verdwijnen van de overlaid Home-actiebalk met Watch Together naar Mijn Pleya (punt 3), en twee
  correcties die de visuele audit afdwong (punt 4). Daarnaast één bevinding buiten de fase die Home
  blootlegde: de rij-uiteinden van `TvDiscoveryRail` zijn harde stops geworden, ook op de
  fase-6-landings.
- **Is er scope blijven liggen?** Ja, dit onderdeel, en dit voorstel is die registratie. Verder twee
  functionele gaten die uit de verwijderde actiebalk volgen (verversen op Home; de Pleya
  Remote-hostsessie op TV), allebei benoemd in DEC-070 punt 3 als fase-9-werk.
- **Klopt de volgende fase nog?** Fase 9 krijgt er drie expliciete onderdelen bij: de ambient
  background, de verversactie en de host-remotesessie op TV. Geen ervan raakt wat fase 8 heeft
  gebouwd.
