# S14/S18: ondertitels behouden bij HLS

Status: geaccepteerd; Michel heeft dit afgebakende venster op 29 oktober 2026 expliciet geopend (DEC-185).

Direct play bevat de ingebedde sporen. De bestaande HLS-uitvoerder gebruikt
`-sn`; `/subtitles/{id}` levert uitsluitend sidecars. Daardoor verdwijnt een
ingebed spoor bij remux/transcode. Dit is resterend werk uit pakket 2 en geen
reden om een kwaliteit die werkelijk wordt uitgevoerd als volledig
ondertitelbewijs te tellen.

## Afgebakende aanvulling

- Optionele capabilities `embedded_subtitles` en `playback_subtitles`, default
  false. De eerste belooft levering van ingebedde sporen via de bestaande
  ondertitelroute; de tweede belooft selectie/off/burn in een playbackplan.
- `GET /subtitles/{subtitle_id}` behoudt sidecarlevering en accepteert achter
  `embedded_subtitles` ook een ingebed spoor. SRT/ASS/SSA/VTT behouden hun
  tekstformaat; PGS/DVDsub kunnen als één subtitle-only Matroska-resource worden
  geleverd (`application/x-matroska`). Er komt geen tweede afspeeltransport.
  Alleen clients die deze externe vorm daadwerkelijk kunnen openen gebruiken
  die levering; anders kan de client het bestaande burn-pad kiezen.
- `PlaybackPlanRequest.subtitle`: optioneel gesloten object met verplicht
  `mode` (`off`, `external`, `burn`) en optioneel `stream_id`. `off` verbiedt een
  stream-id; de andere twee vereisen een stabiel spoor-id én `version_id`.
  Afwezig bewaart het huidige plannerbeleid. Nieuw aanvraagveld uitsluitend
  sturen achter `playback_subtitles`.
- Optioneel antwoordveld `PlaybackPlan.subtitle`: `action` met unknown-safe
  waarden `off`, `external`, `embed`, `burn`, plus optionele `stream_id`, `url`
  en `format`. Een onbekend/onuitgevoerd expliciet besluit is een zichtbare
  fout. Geen stilzwijgende andere taal of uitgeschakelde ondertitel.
- `external` verwijst naar dezelfde geautoriseerde ondertitelroute. `burn`
  dwingt video-transcode af en gebruikt het gevalideerde spoor, met de bestaande
  kwaliteitscap/tone-map/scale en bestaande hardware/softwareterugval. `off`
  levert geen ingebrand spoor en wist de bestaande spelerselectie. Bij een
  wissel blijft de huidige sessie-eigenaar stop/heartbeat/lifecycle beheren.

## Bestaande eigenaars en begrenzing

De gedeelde initialisatie-opties krijgen optionele subtitle-selectie-intentie;
Plex/Jellyfin/local/Share behouden hun huidige defaults en paden. De Pleya-adapter
vertaalt stabiele wire-IDs. De bestaande TrackManager, profielvoorkeuren,
titel/serie-overrides en picker blijven eigenaar van taal en handmatige keuze.
Geen streamindex als onthouden voorkeur en geen automatische fallback
terugschrijven. Ook subtitle-off, forced en ontbrekende taaltag worden getest.

Serverlevering blijft in de bestaande media-/transcodeketen. Extractie gebruikt
een begrensde worker, timeout en maximale uitvoeromvang, dedupliceert gelijktijdige
identieke aanvragen en cachet onder de bestaande cachemap. Cache-identiteit
bevat spoor, versie en bestandsfingerprint; vervangen bron en mislukte extractie
mogen geen oude of halve uitvoer opleveren. Quota/opruiming en annulering zijn
onderdeel van dezelfde wijziging. Alleen serverbepaalde paden/indexen/codecs
bereiken ffmpeg. ASS en bitmap-burn gebruiken een door de server gekozen
subtitlebestand/filter, geen vrije filtertekst uit een request.

Autorisatie op gebruiker, bibliotheek, versie en spoor vindt vóór cache/extractie
plaats en wordt bij levering opnieuw toegepast volgens de bestaande
streamtoken-/sessieregels. Verboden en niet-bestaande IDs blijven ononderscheidbaar.
Geen bearer in een URL of doorsturen naar een wire-host.

## Compatibiliteit en bewijs

1. Nieuwe antwoordvelden zijn optioneel; oude clients negeren ze.
2. Geen veld/route wordt verwijderd of hernoemd.
3. Bestaande sidecar-, versie- en automatische selectiebetekenis blijft gelijk;
   levering voor een voorheen niet ondersteund ingebed id is achter een vlag.
4. Nieuwe aanvraagvelden zijn optioneel met bestaand gedrag bij afwezigheid.
5. De aanvraag blijft gesloten; nieuwe velden alleen achter hun capability.
6. Bestaande gesloten enums veranderen niet. Nieuwe antwoordenum is unknown-safe.

Vóór capability aan: contractfixtures/negatieve validatie, twee gebruikers en
bibliotheken, verlopen/intern ingetrokken sessie, gewijzigde bron, workerlimiet,
timeout/annulering, echte ffmpeg-extractie/burn met ffprobe/beeldcontrole,
publieke appinterface en native speler-load/select/off bij direct play en HLS.
Bitmap/HDR/font-/decodegedrag blijft afzonderlijk per platform en echte hardware
te bewijzen. Het venster omvat uitsluitend deze levering/selectie en consumptie;
geen intro/credits, boeken, loudness, productie of release.
