# Live TV-fixtures

Vastlegging van `epg.provider.plex.tv/settings/favoriteChannels`, gemeten op
17 augustus 2026 tegen een echt Plex-account met een Plex Home van twee
gebruikers. Er staat geen token, cookie, client-id, account-uuid, machine-id of
privé-server-URL in deze map; het meetscript saniteerde de uitvoer voordat hij
werd weggeschreven.

`epg_favorite_channels_contract.txt` is de ruwe vastlegging, inclusief een
afleiding die achteraf ongeldig bleek. Die is als zodanig gemarkeerd en blijft
staan, want zonder dat spoor maakt iemand dezelfde fout opnieuw. De geldige
conclusies staan hieronder en in DEC-021.

## Wat de meting opleverde

**De endpoint eist een token en accepteert er twee soorten.** Lezen met de
PMS-servertoken geeft 200, lezen zonder enige token geeft 401 met
`You must provide a token!`, en lezen met de plex.tv-accounttoken geeft 200 met
een identieke container. Het weglaten van de token is dus geen oplossing voor
het lek; de accounttoken wel.

**Schrijven werkt met beide tokens, voor zover gemeten.** Een lege PUT geeft
zowel met de servertoken als met de accounttoken 200 en verandert niets.

**De endpoint valideert `source` server-side.** Een regel met een verzonnen
provider-source wordt geweigerd met 400 en `Bad source value`, en er wordt niets
opgeslagen: de eindstand was regel voor regel gelijk aan de nulmeting. Daarom
staat die servertekst in `PlexEpgRejected`, want "opslaan werkt soms niet" is
geen diagnose.

**Een 200 zonder `FavoriteChannel`-sleutel is een geldige lege lijst.** Dat is
wat een account zonder favorieten antwoordt, en het is niet hetzelfde als een
mislukte lees. Dat onderscheid is de reden dat `PlexEpgClient` fouten laat
propageren in plaats van ze op te vangen.

## Wat de meting niet opleverde

**De scope van opgeslagen regels is onbekend.** Dit account heeft geen enkele
provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en er
kon geen onderscheidende regel worden weggeschreven. Of `favoriteChannels` per
plex.tv-account of per Plex Home-gebruiker is, valt hiermee niet vast te
stellen.

De meting die het wél zou beslissen: een account met een echte tuner, twee Home
gebruikers, als A een favoriet zetten en als B teruglezen.

## Bestanden

| Bestand | Wat het vastlegt |
| --- | --- |
| `epg_favorite_channels_contract.txt` | De volledige ronde: nulmeting, no-op probe, geweigerde schrijfactie, home-user-lees, opruimen en eindstand, met de ongeldige afleiding gemarkeerd |
