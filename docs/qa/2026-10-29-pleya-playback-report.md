# S14/S17/S18: appaansluiting playback en ondertitels

Ontwikkelbewijs van 29 oktober 2026 op `feat/pleya-server-personal-apps`, vanaf
`9ba3b371`, met lokale wijzigingen. Pakket 2 blijft in uitvoering; dit is geen
release-, productie- of fysieke acceptatie.

## Gedrag en bestaande eigenaars

De Pleya-adapter gebruikt stabiele versie- en spoor-IDs. Een expliciete eerste
versie is te onderscheiden van automatische serverkeuze. Kwaliteitslimieten en
audioselectie gaan alleen achter hun eigen capabilities over de lijn en worden
in planner en ffmpeg uitgevoerd. Expliciete niet-uitgevoerde keuzes worden
geweigerd; er volgt geen stille andere kwaliteit of taal.

De bestaande TrackManager en TrackSelectionService delen hun voorkeuren ook vóór
het openen van HLS. Eerst kiest de server automatisch een versie; uitsluitend
bij een noodzakelijke andere audioselectie of bitmap-burn wordt de voorlopige
sessie gestopt en dezelfde versie opnieuw gepland. De gedeelde taal/moduslaag
blijft eigenaar. Een fallback schrijft geen voorkeur naar de server.

Ingebedde tekstsporen kunnen bij HLS via de bestaande geautoriseerde
ondertitelroute naar de speler. Selectie/off/burn gebruiken het afzonderlijk
vrijgegeven ondertitelvenster. Opaque spoor-UUIDs blijven bewaard naast het
numerieke speler-id; nul blijft gereserveerd voor uit. De bestaande picker,
TV-panel en systeemknoppen gebruiken dezelfde bronwissel. Pleya-beheer blijft web.

Extractie gebruikt één begrensde werker in de bestaande transcodemanager (4 MiB tekst,
64 MiB bitmap, 64 MiB cachequotum), met
deduplicatie, timeout, annulering, bronfingerprint, atomische publicatie en
cacheopruiming. Tekst-burn gebruikt een vaste lokale filterbestandsnaam; een
bron- of cachepad wordt niet in filtertekst geïnterpoleerd. Bitmap-burn gebruikt
een subtitle-only Matroska-bron. Voor levering en het starten van een burn-plan
worden sessie en bibliotheekrecht na voorbereiding opnieuw gecontroleerd.

## Uitgevoerd bewijs

| Controle | Uitkomst |
| --- | --- |
| Lokale `scripts/ci_checks.sh`, ci10 | PASS; format, codegen-freshness, native format, analyze. De drie optionele boombrede linter/unused-scans zijn CI-only |
| Gerichte client/voorkeur/capability/picker-tests | 91 PASS; logs `subtitle-app-regression.log` |
| Gedeelde fixture-/capturetests | 26 PASS, één opt-in capture SKIP; aparte runtimecaptures reeds gevalideerd |
| Gerichte Go playback/transcode/API-regressie | 30 PASS, nul SKIP, met bestaande ffmpeg-image en eigen testdatabase |
| Aanvullende tekst-/bitmap-pixel- en verse-rechtentests | PASS; levering én burn-plan weigeren rechten die tijdens voorbereiding vervallen |
| Protocolschema, statische fixtures en negatieve validatie | PASS, inclusief ontbrekend spoor/versie, uit met spoor en onbekende modus |
| Werkelijke Go-antwoordcaptures tegen OpenAPI | PASS met `--subset`; geen claim van volledige route-dekking |
| Native iOS ondertitelronde | PASS: `ios-pleya-subtitles-1793296919886`, werkelijk playbackRestart, twee geladen tekstsporen, zichtbaar gekozen ingebedde ondertitel, werkelijk speler-id `no` na Uit, geselecteerde pickerregel. Beelden beoordeeld |
| Native tvOS ondertitelronde na reparatie | Functioneel PASS, twee keer: `tvos-pleya-subtitles-1793299589632` en `tvos-pleya-subtitles-1793299864947`. D-pad selecteert werkelijk het ingebedde spoor, Uit geeft speler-id `no`, focus en beide bronrijen blijven geregistreerd; terug/stop bereikt detail. Beelden beoordeeld; zie visuele beperking hieronder |

Negatieve controles: ontbrekende ingebedde HLS-overdracht maakt de publieke test
rood; achtergelaten conversiesessie maakt de vervangingstest rood; onbekende
leveringsmodus liet een sessie achter en wordt nu gestopt; uitgeschakelde burn
levert nul witte pixels en maakt de bitmaptest rood; omzeilen van de verse
bibliotheekcontrole levert ongeoorloofd 200 en maakt de rechtentest rood.

De PGS-fixture is een eigen synthetische witte rechthoek. De packetindeling is
gecontroleerd aan de primaire FFmpeg-implementatie
([SUP demuxer](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/supdec.c),
[PGS decoder](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/pgssubdec.c));
er is geen externe film of dependency toegevoegd. De pixeltest meet verschijnen
op seconde 1 en wissen op seconde 3, op werkelijk gecodeerde 320×180-uitvoer.

Lokale bundels en logs: `.build/pleya-completion-evidence/`. Historische mislukte
native runs blijven bewaard. De oude loading-indicator-check telt niet als
first-framebewijs; de huidige assertions gebruiken het werkelijke native
`playbackRestart`-event. Het HLS-fixturebestand meet 120,075136 seconden,
3536 packets en nul teruglopende DTS. De eerdere discontinuïteitsfixture is
verworpen na native seek-fouten.

## Grenzen van dit bewijs

De native runs gebruiken de bestaande geïsoleerde Verify-app en nepserver met
werkelijk HLS/SRT-transport. Echte serveruitvoer is afzonderlijk met Go/ffmpeg
bewezen. Dit vormt nog geen volledige toestel-naar-NAS-acceptatie. actuele kwaliteitsregressie na de laatste gedeelde reparatie, overige platformen, representatieve bitmap/HDR/fonts,
achtergrond/accountwissel op toestel en PS-5-hardwareronde blijven eigen bewijs.
De bestaande AAC-logmelding over `target_level` is vastgelegd voor C-04; zij is
niet als een bewezen audio-incident aangemerkt.

### Native herhaling en gevonden race

Een herhaling liet de tvOS-speler op de sidecar staan terwijl de bronpicker het
ingebedde spoor had geselecteerd. De oude groene run is geen bewijs dat dit
probleem niet bestond. Er zijn afzonderlijke RED→GREEN-tests voor post-open
`sub-add` en voor Apple dat externe sporen bij open laadt. De bestaande gedeelde
TrackManager wacht nu op de volledige gedeclareerde URI-lijst. De Apple-route
bleef aanvankelijk fout omdat alleen post-open was afgedekt; de extra at-open
test reproduceerde dat. Twee native rondes na die reparatie slagen. Mislukte
bundels blijven bewaard; geen verwachting is afgezwakt.

Verify houdt debugdiagnostiek aan binnen zijn bestaande begrensde en geredigeerde
logger, ook als de productvoorkeur uitstaat. De gewone build volgt die voorkeur
ongewijzigd. Dit is afzonderlijk met en zonder PLEYA_VERIFY getest.

### Visuele beperking tvOS

In de compositoropname na Uit ontbreken nog tekst/een rij, terwijl de UI-tree de
drie juiste bronrijen met afzonderlijke grenzen en de focus op Uit meldt. De
opname met het gekozen ingebedde spoor toont alle rijen en de werkelijke
ondertitel. Dit verschil is niet als geslaagde visuele acceptatie weggeschreven;
het vraagt nader compositor-/toestelonderzoek. Er is geen speculatieve wijziging
in de gedeelde TV-rendering aangebracht.

### Echte geïsoleerde runtime

Voor een aanvullende toestel-naar-API-ronde staat een eigen lokale Go-server op
localhost:18834, met een afzonderlijke tijdelijke Postgres, alleen synthetische
media en een alleen-lezen mediamount. Hij bevat een film van 120 seconden met
twee AAC-talen, ingebedde SRT, sidecar, poster en NFO. Dit is een aanvullende
validatie van de gewijzigde afspeelketen; de eerder bewezen NAS-keten wordt niet
als ontbrekend werk gepresenteerd. Native controle tegen deze runtime loopt nog.
Langdurige playback bij tokenrotatie moet nog expliciet worden gecontroleerd;
een bij open gekopieerde header is op zichzelf geen bewijs van vernieuwing.

### Aanvullende echte keten en regressie

- iOS gedeelde at-open-reparatie: `ios-pleya-subtitles-1793300034454` PASS, gekopieerd naar `.build/pleya-completion-evidence/ios-subtitles-fixed`; ingebedde tekst op native opname beoordeeld.
- Fake-server burn-videobeslissing: test eerst rood (`copy` in plaats van `transcode`), daarna groen. 27 fixturetests PASS; alle 30 vastgelegde antwoorden (ook ondertitel off/external/burn) voldoen aan `openapi.yaml` via `check_server_responses.py --subset`. Geen werkelijk ffmpeg-burnbewijs aan deze fake toeschrijven.
- Echte Go-server + tvOS: kwaliteitskeuze en daadwerkelijk HLS-frame bewezen; native beelden beoordeeld. Bundels `1793301205906` en `1793301330208` behouden als mislukt vervolg. Bij die laatste leverde de nieuwe sessie na ondertitel Uit een404; overlappende stopmelding kan de vervangende sessie wissen. De Pleya-herlaadroute wacht nu op de bestaande stopfuture vóór resolve. Native herhaling met verse build vereist voor sluiting.
- Default `ci_checks.sh`15 PASS (hardlinter en ongebruikte-code/files blijven CI); gerichte appregressie631 PASS/9 voorwaardelijke skips. Dit is geen volledige suite of CI-run.
- Pakket4 gestart met bestaande publieke artworkresolver: stub-test RED→GREEN, alleen canonieke Pleya-artworkpaden. De daadwerkelijke downloadheader/offlineketen is nog open.

### Echte server na de stopreparatie

`tvos-pleya-real-playback-1793301497328` PASS, `.build/pleya-completion-evidence/tvos-real-playback`: directe start, kwaliteitswissel naar20Mbps, werkelijk HLS-frame, ingebed spoor kiezen, werkelijk Uit, terug en stop. Ingebedde tekst is zichtbaar; de off-opname toont alle rijen. De eerdere fake-compositoranomalie blijft als historisch onverklaard beeld behouden, maar is niet op deze echte keten zichtbaar.

`ios-pleya-real-playback-1793301972819` PASS, `.build/pleya-completion-evidence/ios-real-playback`: dezelfde kwaliteits-/ondertitelketen, ingebedde tekst en Uit op native beelden bekeken. Eerdere iOS-pogingen bevatten een sheet-animatie die nog niet af was en een nog bezette enige transcodeplaats na een afgebroken scenario. Fixture-reset verwijdert uitsluitend conversies op de eigen disposable localhostserver en reset alleen de synthetische film. Deze build bevat de stopreparatie, nog niet de later gebouwde downloadwijzigingen.

Downloadvervolg:70 gerichte companion/cache/opslagtests PASS,76 manager/offline-sync-regressies PASS. Na capability- en actieve-knopstatuswijziging: ci17 default PASS en126 gerichte app-/widgettests PASS. Negatieve widgetcontrole zonder mobiele capability-gate toont de downloadknop ten onrechte; terugplaatsen maakt de test groen. Plex/Jellyfin blijven downloaden; een onbekende Pleya-client biedt het niet aan.

Lang afspelen: `TestRefreshDoesNotRenewTheHeaderAlreadyGivenToAPlayer` op echte Go API + geïsoleerde Postgres PASS. Verse API-refresh opent de HLS-afspeellijst, maar het eerder aan de speler gegeven, inmiddels verlopen credential blijft terecht401. Dit is een karakterisering van de bestaande beveiliging en bevestigt dat API-refresh alleen de vastgelegde native header niet vernieuwt; nog geen native duurproef of oplossing. Het verlopen credential langer accepteren is geen reparatie.
