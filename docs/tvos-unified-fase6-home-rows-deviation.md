# Roadmap deviation proposal — fase-6 DoD "Geen duplicate titel in één Home-rij"


> **Afgehandeld afwijkingsvoorstel.** De fase die dit voorstel betrof is gesloten en het
> besluit is doorgevoerd; de statusregel bovenaan zegt hoe. Dit bestand blijft staan als
> de vastlegging van die afwijking. Welke beeldenset vandaag bindt en wat de
> eerstvolgende stap is, staat in [DESIGN-INDEX.md](DESIGN-INDEX.md).

**Datum:** 31 augustus 2026
**Fase:** 6 (Unified Discovery)
**Status:** goedgekeurd door Michel, 31 augustus 2026 — **geleverd en gesloten in fase 8, 31 augustus 2026**
**Vorm:** de zes onderdelen uit hoofdstuk 23.1 van `docs/pleya-server-architecture.md`

Aanleiding: een onafhankelijke read-only systeemaudit op de volledige fase-6-diff
(`875dd91..HEAD`) stelde vast dat de eerste regel van de fase-6 Definition of Done niet geleverd is
en dat er geen enkel besluit onder ligt dat hem uitstelt. Dat laatste is het echte probleem — een
niet-geleverde regel is een planningsvraag, een stilzwijgend niet-geleverde regel is roadmapdrift.
Dit voorstel maakt de keuze expliciet.

---

## 1. De oorspronkelijke aanname

Hoofdstuk 27, fase 6, stelt onder **Werk**: "Groups in Home-rijen; globale row semantics;
sourcepreserving Continue Watching", en onder **Definition of Done** als eerste punt: "Geen duplicate
titel in één Home-rij".

De aanname daarachter was dat de Home-rijen in dezelfde fase op de projectielaag gezet konden worden
als de Films- en Series-landings, omdat het "dezelfde soort rij" is. De fasegrens is destijds
getrokken op *welke data* een rij leest, niet op *welke widget* hem tekent.

## 2. De nieuwe bevinding

De TV Home-rijen worden niet door een fase-6-widget getekend maar door `lib/widgets/tv_browse_rail.dart`
— 2021 regels, en het oudste onderdeel van de TV-UI. Die widget is over zijn volle lengte gebouwd
rond `List<MediaHub>` en `MediaItem`: focusbeheer, scrollpositie, long-press, contextmenu's,
watch-state-badges en activatie (`_activateCurrentItem` → `navigateToMediaItem`) lezen allemaal
rechtstreeks van het concrete item. `DiscoverScreen._tvBrowseHubs` voedt hem met rauwe
`_latestMovies` en `_hubs`.

Twee dingen volgen daaruit, en beide zijn waar:

1. **De DoD-regel is echt niet gehaald.** `getLatestMoviesFromAllServers` klapt alleen *identieke*
   guids samen, dus dezelfde film op twee servers onder twee guids staat als twee kaarten in de
   "Recent uitgebracht"-rij — direct onder een hero die diezelfde twee tot één slide samenvouwt
   sinds [DEC-067](DECISIONS.md#dec-067). Dat is zichtbaar fout, precies zoals DEC-067 het over de
   hero zei.
2. **`TvHomeProjectionProvider.continueWatching` en `.hubs` hebben geen productie-consument.** Ze
   zijn gebouwd, getest en compleet, en er leest niets in `lib/` uit.

## 3. Waarom de roadmap daardoor niet meer klopt

Fase 8's **Toevoegen**-lijst bevat `lib/widgets/tv/tv_content_feed.dart` en
`lib/widgets/tv/tv_content_row.dart`, en zijn **Verwijderen uit de nieuwe TV-home**-lijst haalt de
huidige Home-compositie eruit. Fase 8 vervangt `tv_browse_rail.dart` op Home dus sowieso.

De DoD-regel staat daarmee in fase 6 terwijl de enige plek waar hij waargemaakt kan worden een
widget is die fase 8 weggooit. `TvBrowseRail` nu omzetten naar `UnifiedMediaHub`/`UnifiedMediaGroup`
betekent focus, scroll, long-press, contextmenu en activatie herbouwen in code die één fase later
verdwijnt — exact het argument waarop de roadmap de rowfocus-deferral al heeft geaccepteerd
([DEC-066](DECISIONS.md#dec-066) punt 3, [DEC-067](DECISIONS.md#dec-067) punt 3): "loskoppelen in
fase 6 zou tijdelijke code bouwen die één fase later weer verdwijnt."

Wat niet klopt is dus niet de *eis* — die blijft — maar de fase waarin hij staat.

## 4. De concrete voorgestelde wijziging

1. De DoD-regel **"Geen duplicate titel in één Home-rij"** verhuist van fase 6 naar fase 8, samen met
   de Home-presentatie waar hij aan vastzit. Hoofdstuk 27 wordt op beide plekken bijgewerkt.
2. Fase 6 claimt in plaats daarvan wat hij wél levert, en beperkt de claim expliciet tot de hero en
   de landings: **geen duplicate titel in een discovery-rij op de Films- en Series-landing, geen
   duplicate hero-slide, en unified Continue Watching als geprojecteerde rij.**
3. Fase 8's DoD krijgt de regel er expliciet bij, met de opmerking dat de projectiedata er al ligt
   (`TvHomeProjectionProvider.continueWatching`/`.hubs`) en dat de nieuwe `tv_content_feed`/
   `tv_content_row` die consumeren in plaats van `DiscoverProvider` rechtstreeks.
4. Fase 8's DoD krijgt er ook bij dat Home-rij-activatie via de fase-4-coördinator gaat in plaats van
   `navigateToMediaItem`, zodat een multi-source titel op Home dezelfde source picker krijgt als
   overal elders. Dat hoort bij dezelfde omzetting en zou anders opnieuw stilzwijgend blijven liggen.

## 5. De gevolgen voor latere fasen

Fase 8 wordt groter, en op een voorspelbare manier: hij bouwde al `tv_content_feed.dart` en
`tv_content_row.dart`, en die krijgen er één eis bij die hun databron vastlegt in plaats van
openlaat. Dat is goedkoper dan de omweg, niet duurder — de projectielaag ligt er, getest, met een
bewezen identiteitspijplijn erachter.

Tot fase 8 blijft één zichtbare fout staan: een titel die op twee servers onder verschillende guids
bestaat kan twee kaarten in één Home-rij innemen, en Select op zo'n kaart speelt stilzwijgend één
server af in plaats van de picker te tonen. Dat is bestaand gedrag van vóór fase 6, geen regressie —
maar het is nu wél een geregistreerde uitzondering met een datum eronder in plaats van een gat.

`TvHomeProjectionProvider.continueWatching` en `.hubs` blijven tot fase 8 zonder productie-consument.
Ze zijn niet dood: ze zijn de databron die fase 8's DoD nu bij naam noemt. De
`check-unused-code`/`check-unused-files`-poorten zijn er groen op, want het zijn getters op een klasse
die wél gebruikt wordt.

## 6. Welke scope hierdoor juist vervalt

Uit fase 6 vervalt: het omzetten van `tv_browse_rail.dart` naar de unified projectie, en daarmee ook
het aanpassen van zijn focus-, scroll-, long-press- en contextmenucontracten. Dat is geen uitgestelde
klus die ergens blijft hangen — het is werk dat in fase 6 gedaan en in fase 8 weggegooid zou worden,
en het vervalt dus echt.

Wat **niet** vervalt is de eis zelf. Hij is verplaatst, niet geschrapt, en hoofdstuk 23.1's tweede
helft is hier expliciet van toepassing: een latere productvereiste mag niet versimpeld worden omdat
de huidige fase hem niet nodig heeft.

---

## Roadmap Drift Check (fase 6)

- **Is er iets gebouwd dat niet in de scope stond?** Ja, twee dingen, beide bewust en beide
  vastgelegd: de hero-deduplicatie ([DEC-067](DECISIONS.md#dec-067)) die eerst naar fase 8 geschoven
  was, en de verplaatsing van de catalogusactie naar de paginakop
  ([DEC-068](DECISIONS.md#dec-068)). Verder de DEC-065-punt-4-polish, die als fase-6-werk was
  aangekondigd.
- **Is er scope blijven liggen?** Ja, één regel, en dit voorstel is die registratie.
- **Klopt de volgende fase nog?** Fase 7 (topnav, root-shell, Mijn Pleya) is niet geraakt. Fase 8
  krijgt er twee expliciete DoD-punten bij, hierboven onder 4.

---

## Sluiting — fase 8, 31 augustus 2026

Beide verplaatste eisen zijn geleverd. Ze zitten niet in een controle die de UI uitvoert maar in de
data die hij krijgt en in de ene aanroep die hij doet, wat precies is waarom ze pas hier konden:

1. **Geen duplicate logische titel in één Home-rij.** `TvContentFeed` leest
   `TvHomeProjectionProvider.continueWatching`, `.latestMovies` en `.hubs` — `UnifiedMediaHub`s
   waarvan de identiteitspijplijn de kaarten al heeft samengevouwen, met iedere concrete bron nog op
   `group.sources`. De rij dedupliceert zelf niets en voegt geen title-only fuzzy merge toe. De
   zichtbare fout die dit voorstel registreerde — dezelfde film op twee servers als twee kaarten in
   "Recent uitgebracht", direct onder een hero die ze tot één slide samenvouwt — bestaat niet meer.
2. **Home-rij-activatie via de fase-4-coördinator.** `TvContentRow.onActivate` is
   `ValueChanged<UnifiedMediaGroup>` en de feed geeft die groep door aan
   `TvDiscoveryActivationMixin.activateDiscoveryGroup`. `navigateToMediaItem` komt op dit pad niet
   meer voor. Een multi-source titel in een Home-rij krijgt daarmee dezelfde source picker als
   overal elders.

`TvHomeProjectionProvider.continueWatching` en `.hubs` hebben sinds deze fase een productie-consument;
`.latestMovies` is erbij gekomen omdat de "Recent uitgebracht"-rij dezelfde projectie moet lezen als
de hero zonder diens aftopping op acht te erven.

**Waar het bewijs staat.** `test/screens/tv/tv_content_feed_test.dart` — "one logical title on two
servers is one card, carrying both sources", "a title the pipeline cannot prove equal stays two
cards", "every row activates through the group, never through a concrete item" — plus de
Continue-Watching- en partial-projectietests in hetzelfde bestand, en de negen productierenders in
`test/goldens/tv_home_production_golden_test.dart`.
