# Begrensd venster: beheerde streamsessies voor lange playback

Status: voorstel, geen protocolvrijgave. Roadmap C-05; S14/S18/S15 en S13.

## Probleem en bestaande eigenaar

De native speler krijgt HTTP-headers bij openen. Een API-refresh vernieuwt die
vastgelegde header niet. `TestRefreshDoesNotRenewTheHeaderAlreadyGivenToAPlayer`
bewijst met echte Go API/Postgres dat een verse header de HLS-lijst opent en de
oude, verlopen header terecht401 krijgt. Dit is bron-/API-bewijs; een native
proef met verlopen credential moet de uiteindelijke reparatie nog toetsen.

Bestaande `/auth/stream-session`, `internal/auth/stream_session.go` en de
webcache zijn het uitgangspunt. Er komt geen tweede login- of tokenarchitectuur.
Het HLS-contract belooft `ss` al, maar de server zoekt uitsluitend een
`version_id` in het pad. Ook ontbreekt een publieke eigen stop/heartbeat-route.
De bestaande cookie heeft uitsluitend `/pleya/v1/stream/` als pad; dat draagt
HLS/ondertitels en browserverlenging niet volledig.

## Exacte aanvulling

1. Optionele capability `managed_stream_sessions`, standaard false. Alleen waar
   wanneer de hele onderstaande serverketen werkt. De bestaande vlag
   `stream_sessions` en bestaande create-body blijven behouden.
2. `POST /auth/stream-sessions/{stream_session_id}/heartbeat`: authenticated,
   uitsluitend de actuele login-sessie die de streamsessie aanmaakte. Controle
   van intrekking en versie-/bibliotheektoegang vóór verlenging. Antwoord bestaand
   `StreamSession` met dezelfde id en vernieuwde expiry; geen nieuw geheim in JSON.
3. `DELETE /auth/stream-sessions/{stream_session_id}`: dezelfde eigendomstoets,
   204 bij beëindigen. Vreemd of onbekend geeft404. Geen beheerdersuitzondering
   voor het gebruiken of overnemen van een andere streamsessie.
4. Met de nieuwe vlag zet create/heartbeat dezelfde HttpOnly-secretcookie op drie
   afzonderlijke mediaprefixen: `/pleya/v1/stream/`,
   `/pleya/v1/playback/sessions/` en `/pleya/v1/subtitles/`. Naam blijft
   `pleya_ss_<id>`; Secure/SameSite volgen bestaande regels. Stop wist die drie
   cookies. Geen cookie voor het algemene API- of beheerpad.
5. Bestaande HLS-ss-auth leidt de versie af uit de omzetting en toetst tevens de
   eigenaar van de omzetting. Verkeerde versie, andere gebruiker, ontbrekende
   cookie, ingetrokken account/recht en verlopen sessie worden geweigerd.
6. `/subtitles/{id}` krijgt expliciete optionele `ss` en streamSession-security.
   De versie volgt uit het catalogusspoor. Extractie/levering houdt de bestaande
   dubbele rechtentoets, limieten en intrekkingscontrole.
7. Geen secrets in URLs. Alleen de niet-geheime ss-id reist in media-URLs en
   relatieve HLS-verwijzingen; secret uitsluitend in Cookie/Set-Cookie.

Bestaande fouten volstaan: auth.token_invalid/token_expired en library.not_found;
geen nieuw permissiemodel, database-entiteit of enum nodig. De bestaande
maximale actieve sessies, TTL en single-instance-intrekking blijven gelden.
Ongeldige id/invoer mag geen eigenaar of verborgen media onthullen.

## Client en levensduur

De bestaande playbackinitialisatie/-context krijgt de tijdelijke headers van
precies die opening. API, artwork en downloads behouden hun eigen transport.
Native headers blijven binnen geverifieerde canonieke media-URLs; redirects naar
een andere oorsprong krijgen geen credential. De bestaande speler- en
profielvoorkeuren blijven eigenaar van keuzes.

Start alleen achter de nieuwe vlag; oude servers krijgen geen nieuwe routes of
parameters en behouden hun huidige bearer-pad. De bestaande stop-/vervangings-
en accountgrenzen sluiten de eigen transportlease, ook bij mislukte opening.
Heartbeat houdt een gepauzeerde sessie geldig; sluiten/bronwisselen stopt hem,
zodat snel verschillende titels openen geen acht slots achterlaat. De browser
gebruikt dezelfde lease en vernieuwt daarmee zijn cookie-expiry.

## Compatibiliteit en bewijs

De zes regels: bestaande responses/velden blijven geldig; nieuwe capability is
optioneel false; nieuwe clientvragen zijn capability-gated; fouten blijven
machinecodes; bestaande IDs/versie- en gebruikersisolatie blijven identiek;
oude client/servercombinaties krijgen regressietests en echte antwoordvangsten.

Gerichte publieke clienttests en Go API-tests: verlopen access credential tijdens
actieve lease, seek/nieuw segment, pauze over access-TTL, twee gebruikers,
verkeerde versie, intrekking tijdens levering, herhaalde bronwissel zonder
slotlek, stop/fout/accountwissel en oude server zonder aanvullende requests.
Contract/fixtures plus onafhankelijke adversariële review. Native duurproef op
iOS en tvOS met de eigen geïsoleerde fixture en korte test-TTL; daarna fysieke
platformacceptatie. Geen productie-, merge- of releasevrijgave.
