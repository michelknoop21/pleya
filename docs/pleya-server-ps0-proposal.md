# Roadmap deviation proposal: PS-0 Docker Foundation

**Status:** goedgekeurd, 18 augustus 2026
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md), hoofdstuk 23

Dit voorstel volgt de zes onderdelen uit [hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract).
Het is vastgelegd voordat er een regel servercode is geschreven, en het is goedgekeurd door de
eigenaar van de roadmap. De wijziging is daarmee niet stilzwijgend doorgevoerd.

---

## 1. De oorspronkelijke aanname

De roadmap begint bij PS-1, de protocolspecificatie, en gaat via PS-2 naar een draaiende Go-service.
Daaronder zit de aanname dat de uitvoeringsomgeving een gegeven is: dat een containerimage met een
Go-binary en een Postgres ernaast op de doelhardware gewoon draait, en dat de enige open vragen over
het product gaan.

Hoofdstuk 22 versterkt die aanname. Deployment staat er als een beschrijving van een eindtoestand,
één statisch gelinkte binary plus een containerimage voor `linux/amd64` en `linux/arm64`, met
Postgres als aparte container en read-only mounts. Er staat wat het moet worden, niet dat het nog
bewezen moet worden.

## 2. De nieuwe bevinding

De doelhardware is gemeten in plaats van aangenomen. De Synology DS920+ die het eerste
productiedoel is draait DSM 7.3.2 op **kernel 4.4.302**, met **cgroups v1**, de **btrfs**
storage driver, en een Docker 24.0.2 die als security options **uitsluitend `name=apparmor`**
meldt. Geen seccomp.

Daar komt bij dat de mediabibliotheek over vijf mounts verspreid staat, waarvan er één
`fuseblk.ntfs` is met `user_id=0` en `default_permissions`. De scanner uit PS-2 leunt op stabiele
inodes voor zijn verandersdetectie, en of die aanname op een FUSE-mount houdt is niet af te leiden
uit een ontwerp.

Vier concrete dingen zijn hiermee onbewezen, en alle vier dragen ze elke latere fase:

1. of een actuele Postgres op een kernel uit 2016 met cgroups v1 draait;
2. of een non-root container de NTFS-mount kan lezen;
3. of `read_only`, `cap_drop` en `no-new-privileges` op deze DSM werkelijk pakken;
4. of de inode-aanname van de scanner op elk van de vijf mounts geldt.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

De roadmap plaatst het containerwerk in PS-2, samen met het schema, de scanner, ffprobe en de
leesendpoints. Dat is de fase waarin ook de identiteitsregels en de verandersdetectie landen.

Blijkt daar dat Postgres 18 niet start, of dat de securityopties de container slopen, of dat de
inodes op een van de mounts niet stabiel zijn, dan raakt dat niet een detail van PS-2 maar zijn
fundament. De fase moet dan halverwege terug naar een keuze die er aan het begin al lag, terwijl er
al schema en scannerlogica bovenop staat.

Het is bovendien werk van een andere soort. PS-2 gaat over identiteit, verandersdetectie en
catalogus. Meten of een kernel uit 2016 een database van 2026 draagt is infrastructuur, en die twee
in één fase stoppen maakt het stopcriterium van PS-2 troebel: een scanner die werkt maar in een
container die niet betrouwbaar start is niet af, en het is ook niet duidelijk welke helft faalde.

## 4. De concrete voorgestelde wijziging

Voeg **PS-0 Docker Foundation** toe als fase vóór PS-1.

**Doel.** Aantonen dat een Go-service met Postgres betrouwbaar in Docker op de DS920+ draait, naast
de bestaande Plex-container, met read-only mediamounts.

**Scope.** Een minimale Go-service met configuratie, gestructureerde logging, `/healthz`, `/readyz`
en graceful shutdown. Een multi-stage image die non-root draait. Een Compose-stack met Postgres
zonder hostpoort. Read-only mediamounts. Gescheiden schrijfbare mappen voor duurzame state, cache en
transcode-scratch. Lokale verificatie plus een smoketest op de echte NAS met gemeten resourcegebruik.

**Buiten scope.** Geen protocol, geen `/pleya/v1`, geen schema, geen migraties, geen scanner, geen
ffprobe, geen ffmpeg, geen metadata, geen streaming, geen kijkstatus, geen gebruikers, geen auth.
De service is leeg. Dat is het punt.

**Stopcriterium.** De stack draait op de DS920+, beide healthchecks zijn groen, de media zijn
leesbaar en niet schrijfbaar, de data overleven een herstart, uitval van de database maakt readiness
rood en herstel maakt hem weer groen zonder rebuild, en Plex draait er ongewijzigd naast.

## 5. De gevolgen voor latere fasen

PS-1 tot en met PS-13 behouden hun nummer, hun doel, hun scope en hun stopcriterium. Er schuift
niets op en er verandert niets aan de volgorde. PS-1 blijft de eerste inhoudelijke fase en blijft
uitsluitend tekst en schema's.

PS-2 wordt lichter, maar verliest geen scope. De containerimage staat er nog steeds in, nu met een
bewezen basis eronder in plaats van een aanname. De gepinde ffmpeg blijft expliciet PS-2-werk: PS-0
kiest wel een runtime waar die pin later op past, maar zet er geen ffmpeg in.

De vier metingen uit onderdeel 2 komen beschikbaar vóór PS-1. Valt er een negatief uit, dan is dat
een architectuurblocker die gerapporteerd wordt voordat er een protocol omheen is ontworpen, en niet
halverwege PS-2.

De twee gates uit [hoofdstuk 24.2](pleya-server-architecture.md#242-open-vragen) blijven staan waar
ze staan. PS-0 raakt kijkstatus noch relocatie.

## 6. Welke scope hierdoor vervalt

Geen. PS-0 voegt een fase toe en haalt uit geen enkele bestaande fase iets weg.

Wat wel verschuift is waar het containerwerk voor het eerst wordt aangeraakt. Dat is geen vervallen
scope maar een verplaatsing, en PS-2 houdt zijn eigen containerverantwoordelijkheid: de image met de
gepinde ffmpeg, het schema en de migraties horen daar en komen daar.

De replacement matrix wordt door dit voorstel niet gewijzigd. PS-0 levert geen enkele capability uit
die matrix af, en de Plex-off gate blijft rood.
