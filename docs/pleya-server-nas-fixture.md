# De NAS-migratiefixture

`pleya_server/internal/testsupport/fixtures/nas-schema7.sql` is een geanonimiseerde steekproef uit
de Pleya Server die op de NAS draait. Hij bestaat omdat een migratie die op een leeg schema slaagt
niets bewijst over een gevulde installatie: een kolom die niet nullable mag worden, een backfill die
op nul rijen klopt en een constraint die pas op echte data bijt komen daar alle drie niet uit. Dit is
taak S0.6 uit `docs/PLEYA-SERVER-MASTERLIST.md` en J.7 uit
`docs/pleya-server-rebaseline/J-api-schema-migratie.md`.

## Herkomst

Gemaakt op 4 september 2026 uit de container `pleya-server-db` (`postgres:18.6-bookworm`) op de
Synology. De database stond op schemaversie 7, gelijk aan de hoogste migratie in de code op dat
moment. Er is uitsluitend gelezen: `COPY (SELECT …) TO STDOUT` plus twee tijdelijke views in de
psql-sessie zelf. Geen enkele productietabel is aangeraakt.

Bij het ophalen is de structuur van de draaiende database vergeleken met wat `0001` tot en met `0007`
opleveren. Ze zijn gelijk. Het enige verschil is de tabel `schema_migrations`, die de migratierunner
zelf aanmaakt en dus niet in de SQL-bestanden staat, plus een commentaarregel die op de NAS nog
DEC-065 noemt waar de code inmiddels DEC-098 zegt; dat is de hernummering van diezelfde dag en geen
drift.

## Waarom een steekproef en geen volledige dump

De NAS draagt 7410 items, 29176 bestanden en 37167 streams. Dat volledig in de repo zetten kost
tientallen megabytes voor een testbestand, en een migratietest wordt er niet sterker van: wat een
migratie sloopt zijn vórmen, niet aantallen. De steekproef is daarom gericht samengesteld en telt
131 items, 242 versies, 712 bestanden en 964 streams, in ruim een megabyte.

Wat er bewust in zit, met de reden:

| Vorm | Waarom |
| --- | --- |
| alle drie de bibliotheken en alle vijf de opslaglocaties | waaronder de twee met `inode_trusted = false` op NTFS, het pad waar relocatie anders werkt |
| vier series, elk met twee seizoenen en acht afleveringen | de hele boom film, serie, seizoen, aflevering, inclusief de `parent_kind`-constraint |
| veertig films plus de complete kinderbibliotheek | twee bibliotheken met dezelfde soort, wat de scheiding op `library_id` uitoefent |
| elke container die niet `mkv` is | `mp4` en de enige `wmv` op het hele systeem |
| versies met 1, 2, 3, 4, 5, 6 en 8 bestanden | de fan-out van versie naar bestand, tot en met het geval dat `409 library.version_multifile` uitlokt |
| de twee bestanden met `missing_since` | de enige rijen op het systeem die een verdwenen bestand beschrijven |
| alle vier de kijkstatussen | de server is er eigenaar van (DEC-049), dus een migratie mag er geen kwijtraken |
| alle 219 refreshtokens | inclusief ingetrokken tokens en de `replaced_by`-ketens uit DEC-096 |
| alle sessies, jobs en scanruns | klein genoeg om volledig te zijn |

De ouderafsluiting draait twee ronden, zodat een aflevering die om een andere reden in de steekproef
belandt zijn seizoen en zijn serie meesleept en de boom heel blijft.

## Anonimisering

Wat vervangen is: alle titels en sorteertitels van films, series en afleveringen; de
`grouping_key` van items en versies; elk `relative_path`; `scan_signature` en `content_fingerprint`;
titels op streams; de gebruikersnaam en wachtwoordhash van de eigenaar; elke tokenhash; apparaat-id's
en apparaatnamen; foutteksten en het lopende pad op scanruns.

Wat bewust blijft staan, omdat het structuur is en geen naam: de bibliotheekslugs en -titels
(`films`, `series`, `kids`), de containerpaden van de opslaglocaties (`/media/library/Films`), codecs,
profielen, talen, kanaalindelingen, resoluties, groottes, tijdstempels, uuid's en de
`detection`-jsonb. Die laatste is nagekeken en bevat alleen herkomstlabels als
`{"source": "ffprobe_stream", "status": "confirmed"}`, geen vrije tekst.

Twee dingen moesten meebewegen met de vervangingen, anders weigert het schema de fixture. De kolom
`replaced_by` is een self-FK naar `token_hash`, dus beide gaan door dezelfde afbeelding en de
rotatieketen blijft heel. En `(item_id, grouping_key)` en `(storage_location_id, relative_path)` zijn
uniek terwijl de tekst die ze onderscheidde er nu uit is; wat na de herbouw samenvalt krijgt daarom
een teller (` v2`, `-2`).

## De garantie

Niet de zorgvuldigheid van de vervangingen, maar een lekcontrole die er los van staat. Die leest de
ruwe vangst opnieuw, verzamelt elke oorspronkelijke titel, elk pad, elke bestandsnaam, elke hash en
elke gebruikersnaam, en zoekt ze allemaal terug in het gegenereerde bestand. Op de opgeleverde
fixture zijn 2495 identificerende waarden gecontroleerd en geen ervan komt erin voor. Op een
vervuilde kopie slaat dezelfde controle wel aan, dus hij kan een lek zien.

Waar de controle een grens trekt: een waarde telt als identificerend zodra hij uit meer dan een woord
bestaat of minstens twaalf tekens lang is. Zonder die grens slaat hij aan op losse woorden die ook
elders legitiem voorkomen, zoals een stream-titel "Stereo" tegen `channel_layout = 'stereo'` en
"Forced" tegen de kolomnaam `is_forced`. Tweeënzeventig van zulke korte woorden zijn opzijgezet. Een
los woord identificeert geen film; een titel, een pad of een hash wel.

De ruwe vangst is in de scratchpad van de sessie gebleven en staat niet in git.

## Vernieuwen

Het ophaal- en anonimiseerscript staat niet in de repo, want het is eenmalig werk met een verbinding
naar productie erin. Wie de fixture wil vernieuwen: lees dit hoofdstuk, haal opnieuw op met dezelfde
bemonstering, en draai de lekcontrole voordat er iets gecommit wordt.
`TestNASFixtureCoversTheShapesItWasSampledFor` bewaakt de tabel hierboven, dus een vernieuwde vangst
die een vorm kwijtraakt valt daar om.

## Wat de test er vandaag mee bewijst, en wat nog niet

`TestNASFixtureSurvivesMigrationToHead` zet de database op 7, laadt de fixture, migreert naar de
huidige versie en eist dat de bibliotheek-id's en -slugs, het aantal items per bibliotheek, elke
kijkstatus met zijn positie en de rijaantallen van tien tabellen er onveranderd doorheen komen,
plus dat de schemaversie daarna gelijk is aan wat de binary wil.

De migratiestap zelf is nu leeg: de NAS staat op 7 en de code ook. De test bewijst daarmee vandaag
dat de fixture laadt, compleet is en de vormen draagt waarvoor hij bemonsterd is, en niet meer dan
dat. Vanaf `0008` is het de plek waar elke migratie haar bewijs neerlegt, en dan gaan de asserties
er echt overheen. Dat is de reden dat hij nu al bestaat en niet pas bij de eerste migratie die hem
nodig heeft.
