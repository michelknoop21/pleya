# Roadmap deviation proposal: een eigen werkpakket "loudnessmeting" naast PS-11A

**Status:** goedgekeurd, 11 september 2026 (D0)
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 23 en 24,
[docs/pleya-server-gates.md](pleya-server-gates.md) secties 7-8, `CLAUDE.md`

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het gaat uitsluitend
over het toevoegen van een zelfstandig werkpakket naast de bestaande dertien fasen; geen enkele
bestaande fase verandert van inhoud, volgorde of scope. Het wordt niet automatisch doorgevoerd: D1
(schema) begint pas na akkoord op dit document.

---

## 1. De oorspronkelijke aanname

Hoofdstuk 23's fasetabel is de volledige lijst van wat de server met een bestand doet: catalogiseren
(PS-2), afspelen (PS-4/PS-4E/PS-4W), apparaatprofielen en planning (PS-5/PS-6), metadata en
sidecars (PS-7/PS-7N/PS-7A), transcoderen (PS-8), gebruikers en rechten (PS-9), beheer (PS-11A),
enzovoort. Nergens in die lijst, en nergens in `CLAUDE.md`, staat een activiteit die een audiostroom
leest, meet en het resultaat opslaat zonder er een afgeleid bestand van te maken. De impliciete
aanname was dat elke aanraking van een audiostroom óf catalogiseren is, óf transcoderen: er is geen
derde categorie voorzien.

Diezelfde aanname zit in de client: loudness-normalisatie is tot nu toe uitsluitend client-owned
geweest (DEC-101, en na de zojuist geland C1-C4 ook DEC-111 op `main`), met de server als bron van
alleen de rauwe bytes en eventuele codec-tags.

## 2. De nieuwe bevinding

De client-kant van de Pleya Unified Loudness Engine (`loudness-engine`, geland als DEC-111) bewijst
dat gain-only client-DSP een consistente uitgangsluidheid haalt, maar de kwaliteit van die gain hangt
af van wat de client aan invoer heeft: een realtime meter die tien seconden nodig heeft om te
convergeren, of een codec-tag (Opus `R128_TRACK_GAIN`) die kan liegen. Beide gaten zijn in DEC-111
expliciet als open risico vastgelegd, niet als opgelost.

Eén ffmpeg `loudnorm`-analysepas per audiostroom, server-side, eenmalig, zonder her-encoderen, geeft
elke client vanaf de eerste seconde een precies meetresultaat en een onafhankelijke controle op een
tag die de client anders blind moet vertrouwen. Dat is een echte derde categorie: geen catalogisering
(geen nieuwe bestanden, geen mediastructuur), geen transcodering (geen uitvoerbestand, geen
her-encodering, geen PS-8-machinerie nodig), en geen metadata in de PS-7-zin (geen externe NFO of
artwork-bron; het resultaat is berekend, niet gelezen). PS-2, PS-7 en PS-8 dekken hem geen van drieën.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

De roadmap klopt inhoudelijk: er is geen fout in wat er staat. Wat ontbreekt is een plek voor een
read-only meetresultaat per stream, met een eigen opslagvorm en een eigen jobsoort, die geen van de
bestaande fasen zonder scope-geweld kan herbergen.

In PS-8 zetten zou "build the extension early" zijn: PS-8 is niet gestart, en een analysepas heeft
niets met een transcoder-pool te maken behalve dat beide ffmpeg aanroepen. In PS-7 zetten zou het
sidecar/NFO-precedent misbruiken voor een waarde die de server zelf berekent in plaats van van een
externe bron leest. Niets doen en het client-only houden is ook een keuze, en een dure: elke
afspeelstart blijft dan de realtime-convergentietijd betalen die DEC-111 al als bekende beperking
vastlegt, terwijl er een goedkope, eenmalige serverpas voor bestaat.

Er is dus geen fout in de roadmap om te herstellen, wel een gat om te vullen: een plek voor
analyse-only werk dat noch scan, noch transcode, noch metadata is.

## 4. De concrete voorgestelde wijziging

**Een nieuw, zelfstandig werkpakket "loudnessmeting", naast PS-11A, niet erin en niet erop
wachtend.** Precedent is de vorm van PS-7 (een serverzijdig resultaat dat additief aan een stream
hangt, opgeslagen als eigen gegeven), toegepast op een geanalyseerde in plaats van gelezen waarde.

Vijf onderdelen, D1 tot en met D5, uitgewerkt in het plan (`pleya-unified-loudness-engine-steady-moon.md`,
stap D):

- **D1, schema.** Eén nieuwe tabel `stream_loudness`, FK naar `media_files`, `generation`-gebonden
  geldigheid, geen `pending`-status (de jobtabel is de wachtrij).
- **D2, package `internal/loudness`.** Eén ffmpeg-pass per stream (`loudnorm`, `-f null -`, geen
  uitvoerbestand), plus een allowlist voor vertrouwde codec-tags (alleen Opus `R128_TRACK_GAIN`).
- **D3, job.** Nieuwe jobsoort `analyze_loudness` op het bestaande job/workermodel
  (`scanwork.go`/`storagework.go`-patroon), eigen workerpool, uit te zetten via config (`0` =
  rollback).
- **D4, vraagsturing.** Enqueue vanuit de bestaande afspeelverzoek-handlers, geen nieuw endpoint,
  geen protocolwijziging.
- **D5, API-veld.** Pas ná D1-D4 bewezen zijn: één additief, optioneel veld op de bestaande
  stream-representatie.

**Wat dit expliciet niet is:** geen wijziging aan de dertien fasen of hun volgorde, geen ffmpeg als
transcoder (dat blijft PS-8), geen server-owned normalisatie (de client past de gain nog steeds zelf
toe; de server levert alleen het meetbewijs).

Dit document dekt alleen D0. D1 begint pas na akkoord hierop.

## 5. De gevolgen voor latere fasen

PS-8 verliest niets: transcoderen blijft zijn scope, en de analysejob schrijft nooit een
uitvoerbestand, dus er is geen overlap om te verdelen. PS-9 en PS-11A verliezen niets en krijgen
niets erbij: loudnessmeting heeft geen afhankelijkheid op gebruikers/rechten en claimt geen
`admin`-oppervlak; het draait naast PS-11A, niet erop wachtend en het niet blokkerend.

**Protocolvenster.** D1 tot en met D4 raken het protocol niet (schema, intern package, job,
vraagsturing via bestaande handlers) en kunnen dus ongeacht de venstertoestand door. D5 raakt het
wél: een nieuw optioneel responsveld voldoet aan compatibiliteitsregel 1
(`docs/pleya-protocol/v1/openapi.yaml` hoofdstuk 3), maar het venster dat nu open staat voor S2 van
PS-11A ([DEC-136](DECISIONS.md), hernummerd op 20 en 25 september 2026, eerder DEC-113 en DEC-133) is beperkt tot precies
de tien wijzigingen uit `docs/pleya-server-rebaseline/J-api-schema-migratie.md` J.3. Het
`Loudness`-veld staat daar niet bij, dus D5 mag niet meeliften op dat venster. D5 heeft, wanneer D1-D4
bewezen zijn en D5 daadwerkelijk klaarstaat, een eigen vensteropening nodig, volgens hetzelfde
precedent als de drie eerdere openingen (DEC-101, DEC-110/DEC-112, DEC-113). Dit voorstel vráágt dat
venster nu niet aan; dat blijft bewust een latere, losse beslissing, gelijk aan de volgorde in het
plan (stap E wacht op zowel C2 als D5).

**DEC-nummering.** Deze branch (`feat/loudness-server-analysis`, vanaf
`integration/pleya-server-rebaseline`) staat op DEC-113 als laatst gebruikte nummer; `main` (met de
zojuist geland C1-C4) staat op DEC-111. De twee lijnen lopen uiteen tot een volgende main-sync. Een
D1-besluit op deze branch wordt dus voorlopig DEC-114 hier, en kan bij het samenvoegen met main
opnieuw genummerd moeten worden, hetzelfde patroon als eerder beschreven bij de main-sync van
6 september 2026.

## 6. Welke scope hierdoor vervalt

Geen. Dit voegt een zelfstandig werkpakket toe naast de bestaande dertien fasen. Er wordt niets aan
een bestaande fase geschrapt, versimpeld of naar voren gehaald.

Dat onderdeel 6 leeg is hoort er expliciet te staan: een leeg vakje en een niet-ingevuld vakje zien
er in dit sjabloon hetzelfde uit.
