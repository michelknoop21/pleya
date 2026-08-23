# Roadmap deviation proposal: PS-5 → PS-9 → PS-11A vóór de rest van de playbackketen

**Status:** goedgekeurd, 23 augustus 2026
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 23,
[docs/pleya-server-masterplan-proposal.md](pleya-server-masterplan-proposal.md) hoofdstuk 16,
[CLAUDE.md](../CLAUDE.md)

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is vastgelegd
voordat er een regel PS-5-code is geschreven. Het gaat uitsluitend over de volgorde waarin fasen
worden uitgevoerd; geen enkele fase verandert van inhoud.

---

## 1. De oorspronkelijke aanname

De fasetabellen in hoofdstuk 23 dragen twee velden die over volgorde gaan: **Afhankelijkheden** en
**Eerstvolgende fase**. PS-5 heeft `Afhankelijkheden: PS-4` en `Eerstvolgende fase: PS-6`, PS-6 wijst
door naar PS-7, en zo verder. Gelezen als een ketting beschrijven die velden samen één lineair pad:
PS-5, PS-6, PS-7, PS-8, en pas daarna de rest.

`CLAUDE.md` heeft die lezing overgenomen. Er staat dat PS-5 de eerstvolgende fase is en dat werk
buiten de PS-5-scope per definitie te vroeg is, met gebruikers (PS-9) er expliciet bij genoemd als
voorbeeld van te vroeg.

Achter beide zit dezelfde aanname: dat "Eerstvolgende fase" een uitvoeringsopdracht is, en niet een
leeswijzer.

## 2. De nieuwe bevinding

De twee velden spreken elkaar tegen zodra de graaf vertakt, en hij vertakt.

De mermaid in [23.2](pleya-server-architecture.md#232-de-volgorde-en-waarom-hij-zo-is) tekent
`P4 --> P9`. PS-9 hangt dus aan PS-4 en niet aan de playbackketen. Het masterplan bevestigt dat in
16.2 en corrigeert daar juist een keten die gebruikers achter web playback zette: gebruikers hangt
aan PS-4, punt. Diezelfde vertakking geldt voor PS-7, dat alleen de catalogus nodig heeft.

Nergens staat wat "Eerstvolgende fase" betekent op een plek waar de graaf twee kinderen heeft. Bij
PS-4 heeft het veld één waarde terwijl de graaf er twee toestaat, en dat is precies de plek waar dit
voorstel begint.

De tweede bevinding is productinhoudelijk. PS-11A ("Serverbeheer via het protocol") is het grootste
enkele gat richting Plex dat vandaag open staat: medialocaties komen uit één omgevingsvariabele, en
een bibliotheek toevoegen betekent een `.env` bewerken en de container herstarten. PS-11A hangt aan
PS-9 voor de klasse `admin`, PS-9 hangt alleen aan PS-4, en PS-4 is gesloten. De route naar dat gat
loopt dus volledig langs fasen die vandaag al vrijgegeven kunnen worden.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

De roadmap klopt inhoudelijk wel. Wat niet klopt is de regel die eruit gelezen wordt.

Zolang "Eerstvolgende fase" als opdracht geldt, verbiedt `CLAUDE.md` een fase die de
afhankelijkheidsgraaf gewoon toestaat. Dat is geen bescherming maar een leesfout die als bescherming
werkt: iemand die PS-9 wil oppakken moet dan kiezen tussen de graaf en de tekst, en de tekst is
normatief. Het gevolg is dat het grootste productgat blijft liggen achter drie fasen die er geen
enkele technische afhankelijkheid mee delen.

De regel die wel moet blijven staan is de andere: werk binnen één Phase ID, en bouw niets van een
latere fase vooruit. Die regel wordt hier niet aangeraakt en wordt door dit voorstel ook niet
zwakker. Wat verandert is welke fase "de huidige" is, niet hoe strak de grens eromheen zit.

## 4. De concrete voorgestelde wijziging

**De uitvoeringsvolgorde wordt PS-5, PS-9, PS-11A, en daarna PS-6, PS-7, PS-8.** De
afhankelijkheidsgraaf blijft ongewijzigd; deze volgorde is er een geldige doorloop van.

PS-5 gaat er als eerste doorheen om twee redenen die los van elkaar staan. Het legt de harde invoer
van de playbackplanner vast, dus PS-6 wordt er goedkoper van in plaats van duurder. En het verbetert
Plex en Jellyfin vandaag al, want beide krijgen nu een `const` profiel dat het toestel niet kent, dus
het levert waarde ook als Pleya Server zou vertragen.

**Het veld "Eerstvolgende fase" krijgt een gedefinieerde betekenis.** Het is een leeswijzer die de
hoofdlijn van de graaf aanwijst, niet een uitvoeringsopdracht en niet een tweede
afhankelijkheidsregel. Bindend is uitsluitend het veld **Afhankelijkheden**, samen met de mermaid in
23.2. Waar de graaf vertakt mag elke fase waarvan de afhankelijkheden gesloten zijn als volgende
worden opgepakt. Die definitie komt in 23.2 te staan, direct onder de mermaid, zodat hij gelezen
wordt op de plek waar de vertakking zichtbaar is.

**De vier plekken die meeveranderen.** Het veld "Eerstvolgende fase" van PS-5 wijst voortaan naar
PS-9 met PS-6 als tweede lezing, de mermaid krijgt de definitie eronder, de PS-5-alinea in
`CLAUDE.md` noemt de gekozen route in plaats van één volgende fase, en hoofdstuk 23 van het
masterplan krijgt een rij die deze volgorde vastlegt.

## 5. De gevolgen voor latere fasen

PS-6, PS-7 en PS-8 verliezen niets. Ze schuiven op in de tijd en houden hun scope, hun
acceptatiecriteria en hun afhankelijkheden. PS-6 wint zelfs: hij krijgt zijn invoer uit een model dat
dan al op hardware bewezen is in plaats van uit een model dat in dezelfde ronde ontstaat.

PS-9 en PS-11A verliezen niets en krijgen niets erbij. Ze worden eerder uitgevoerd, met dezelfde
inhoud die er vandaag staat.

De protocolvriezing schuift mee. `docs/pleya-protocol/v1/openapi.yaml` blijft bevroren zolang PS-5
loopt. PS-5 raakt het contract niet: het wire-oppervlak voor capabilities is expliciet PS-6-scope, en
het woord `capabilities` in de YAML slaat op de featurevlaggen van de server, niet op die van een
toestel. Dat de volgorde verandert, verandert dus niets aan wanneer het venster opengaat.

De vijf poorten bewegen niet. Ze staan alle vijf dicht en geen ervan hangt aan een fase die hier
verschuift.

## 6. Welke scope hierdoor vervalt

Geen. Dit is een volgorde-afwijking en geen scope-afwijking. Er wordt niets geschrapt, niets
versimpeld en niets naar voren gebouwd; er verandert uitsluitend in welke volgorde bestaande,
ongewijzigde fasen worden uitgevoerd.

Dat onderdeel 6 leeg is hoort er expliciet te staan, want een leeg vakje en een niet-ingevuld vakje
zien er in dit sjabloon hetzelfde uit.

---

## Bijlage: vier documentcorrecties die hiermee meelopen

Deze vier zijn tijdens de controle boven water gekomen. Ze horen niet bij de afwijking, maar ze staan
in dezelfde documenten en kosten hier samen een handvol regels.

| # | Plek | Wat er staat | Wat het wordt |
| --- | --- | --- | --- |
| 1 | `docs/pleya-server-gates.md` | het protocol is bevroren "voor de duur van PS-4" | PS-4 is gesloten, dus bevroren zolang PS-5 loopt, gelijk aan `CLAUDE.md` |
| 2 | masterplan hoofdstuk 23 | PS-4 "opgeleverd en ter goedkeuring, criterium 1 nog niet gedaan" | PS-4 is gesloten op 21 augustus 2026, met alle drie de vormfactoren op hardware |
| 3 | architectuur hoofdstuk 9 | de containerlijst uit masterplan 11.1 staat er niet | de lijst hoort bij de decoderlaag en wordt daar benoemd, met de verwijzing naar het masterplan |
| 4 | `pleya_server/README.md` | "twaalf tabellen", "negen endpoints van de zeventien" | elf tabellen, veertien endpoints, gelijk aan de tabel eronder |

Correctie 4 wees het masterplan aan PS-11A toe omdat dat de eerstvolgende fase is die de README
aanraakt. Twee getallen rechtzetten kost hier één regel per stuk, en de tegenspraak met de tabel
eronder staat er al sinds de goedkeuring.
