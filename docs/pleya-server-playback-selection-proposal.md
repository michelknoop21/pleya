# S14/S17/S18: expliciete kwaliteit en audiokeuze

Status: geaccepteerd en afgebakend venster geopend door Michel op 29 oktober 2026 (DEC-XXX).

De publieke appinterface draagt al `qualityPreset`, `selectedAudioStreamId` en
`selectedMediaSourceId`. Alleen de stabiele versie past in het bestaande
`PlaybackPlanRequest.version_id`. De aanvraag is gesloten; de bestaande
`capabilities.connection.max_bitrate_kbps` beschrijft de verbinding en draagt
geen expliciete uitvoerresolutie of audiokeuze. Het bestaande automatische
versiebeleid blijft gelden wanneer `version_id` ontbreekt.

## Afgebakend venster

Voeg twee optionele velden toe aan `PlaybackPlanRequest`:

- `quality`: gesloten object met verplicht `max_video_bitrate_kbps` (geheel
  getal, 1–100000) en `max_height` (geheel getal, 1–4320). Ontbrekend betekent
  bestaand plannerbeleid. De app vertaalt de bestaande presets; original laat
  het veld weg. Geen nieuwe presets, encoder of hardwareaanname.
- `audio_stream_id`: bestaand opaque ID uit de `audio_streams` van de gekozen
  versie. Ontbrekend betekent bestaand beleid. Aanwezig vereist `version_id`;
  de app vertaalt het bestaande geselecteerde streamindexnummer naar het wire-ID
  binnen die versie. Een ontbrekend/verwijderd spoor is een zichtbare fout,
  geen stilzwijgende andere taal.

De server adverteert aparte capabilities `playback_quality` en
`playback_audio_selection`, standaard false. Een true vlag betekent dat
validatie, planner en ffmpeg de keuze daadwerkelijk uitvoeren. Het antwoord
krijgt optionele `selected_audio_stream_id` en `effective_quality`, zodat de
client de effectieve keuze kan controleren. Bij een onuitvoerbare expliciete
keuze volgt een bestaande foutvorm met een specifieke code; de client valt
voor die keuze niet stilzwijgend terug op original/defaultaudio. Automatische
playback zonder deze velden behoudt de bestaande fallback.

De server valideert eerst gebruiker, bibliotheek, item, versie en spoor. De
planner selecteert het gevraagde spoor vóór codecbeoordeling; ffmpeg gebruikt
het gevalideerde bronindexnummer. Een kwaliteit boven de bron vergroot de bron
niet. De cap bereikt zowel software- als bestaande hardware-encodepaden. Een
nieuwe sessie vervangt de bestaande sessie via de huidige stop/heartbeat-flow.

## Zes compatibiliteitsregels

1. Nieuwe antwoordvelden zijn optioneel; oude clients negeren ze.
2. Geen veld wordt verwijderd of hernoemd.
3. Bestaande betekenis blijft gelijk, inclusief connection-capabilities.
4. Nieuwe aanvraagvelden zijn optioneel; afwezig reproduceert het huidige gedrag.
5. De aanvraag blijft gesloten. Nieuwe clients sturen elk veld uitsluitend
   achter de eigen servervlag. Oude/ontbrekende vlag betekent geen nieuwe velden
   en geen publieke kwaliteitsactie; geen proefrequest naar een oude server.
6. Geen bestaande gesloten enum krijgt een waarde erbij.

Bewijs vóór capability aan: gesloten-body/API/contractfixtures, oude client op
nieuwe server, nieuwe client op oude server zonder nieuwe velden, verwijderde
versie/spoor, bibliotheekisolatie, cap/ffmpeg-argumenten, werkelijke uitvoer met
ffprobe op geïsoleerde fixtures, publieke appinterface en spelerwissel/stop.
Decoder/HDR/native hardwareacceptatie blijft een afzonderlijk platformbewijs.
Het venster omvat uitsluitend deze velden, vlaggen, validatie en consumptie;
geen boeken, loudness, collecties, events of productie.
