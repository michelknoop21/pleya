# Tautulli-contracten, gemeten tegen een echte instance

Gemeten op 17 augustus 2026 tegen Tautulli v2.17.2 (Python 3.13.13) achter de eigen Plex-server.
Alleen lezende commando's; er is niets geschreven, verwijderd of herstart.

Gesaniteerd: API-key, gebruikersnamen, e-mailadressen, Plex-accounthashes, machine-id's en
IP-adressen. Van een IP is alleen bewaard óf het LAN of WAN was, want de UI kan `location`
gebruiken; het adres zelf staat er niet meer in. Veldnamen en waardeformaten zijn onaangeroerd.

## De belangrijkste uitkomst: authenticatie kan niet per gebruiker

Dit bepaalt het hele ontwerp, dus het staat bovenaan.

`plexpy/api2.py` accepteert precies drie dingen, en geen ervan is een Plex-account:

```python
# api2.py:126-135
if not self._api_app and self._api_apikey == plexpy.CONFIG.API_KEY:
elif self._api_app and mobile_app.get_temp_device_token(...) and cmd == 'register_device':
elif self._api_app and mobile_app.get_mobile_device_by_token(self._api_apikey):
```

Tautulli heeft wél Plex-OAuth, maar alleen voor de webinterface: `plexpy/webauth.py`
(`plex_user_login`) zet een JWT-cookie `tautulli_token_`, en `api2.py` kijkt daar nooit naar.
`get_apikey` is uit de API verwijderd.

Vergelijk met Jellyseerr, waar Pleya wél per gebruiker inlogt (`seerr_client.dart:98`,
`POST /auth/plex`). Jellyseerr heeft accounts per gebruiker; Tautulli heeft één beheerderssleutel.

En die sleutel opent alles. Van de 125 commando's op deze instance zijn onder meer beschikbaar:
`sql`, `download_database`, `download_config`, `delete_all_user_history`, `delete_user`,
`get_user_ips`, `terminate_session`, `restart`, `update`. Er is geen read-only variant en geen
scoping per gebruiker. Een Tautulli-sleutel op het toestel van een eindgebruiker zetten is dus
gelijk aan die persoon beheerderstoegang geven tot de server.

## Wat we willen tonen, en waar het vandaan komt

### `get_item_user_stats`: wie keek deze titel

`item_user_stats_movie.json`, `item_user_stats_show.json`

Eén call per titel, en het antwoord is precies de rij die de detailpagina nodig heeft:

```json
[{"friendly_name":"user67","user_id":4725462,
  "user_thumb":"https://plex.tv/users/<hash>/avatar?c=1786978661",
  "username":"user67","total_plays":3,"total_time":6272}]
```

`user_thumb` is een echte, tokenloze plex.tv-avatar. Dat is het gat dat de Plex-meting
achterliet: `/accounts` op de PMS gaf bij alle 23 accounts een lege `thumb`.

Werkt met de rating key van een film én van een serie. Op serieniveau telt hij alle
afleveringen op (in deze set: 153 plays voor één gebruiker), wat de juiste betekenis geeft voor
"kijkt deze serie" zonder dat we iets hoeven af te leiden.

**Let op:** `total_plays` telt óók afgebroken kijkbeurten mee. In `history_movie.json` staat een
rij met `percent_complete: 10` en `watched_status: 0`, en die zit in de 3 plays van die
gebruiker. Wie deze call gebruikt en er "heeft bekeken" boven zet, liegt. Zie hieronder.

### `get_history`: de precieze betekenis van "bekeken"

`history_movie.json`, `history_show.json`

Per kijkbeurt, met onder meer `watched_status` (0 of 1), `percent_complete`, `date`,
`platform`, `player`, `transcode_decision`, `location`, `duration`, `paused_counter` en
`user_thumb`. Er is **geen** parameter om op `watched_status` te filteren, dus dat gebeurt aan
onze kant.

Voorstel dat bij het contract past:

- **Film**: `get_history?rating_key=X`, filter op `watched_status == 1`. Weinig rijen, precies.
- **Serie**: `get_item_user_stats?rating_key=<show>`, met een label dat over kijken gaat en
  niet over uitkijken. Per aflevering filteren is hier zinloos en zou 154 rijen kosten.

### `get_users`: namen en avatars

`users.json`

17 gebruikers, **allemaal met een `thumb`**. Verder `user_id`, `username`, `friendly_name`,
`email`, `is_admin`, `is_active`, `is_home_user`, `is_restricted`, `shared_libraries`,
`keep_history`, `allow_guest` en de `filter_*`-velden.

`friendly_name` is de naam die de beheerder in Tautulli heeft ingesteld en is de juiste om te
tonen; `username` is het Plex-account.

### `get_activity`: nu aan het kijken

`activity_idle.json` (leeg, want er keek niemand)

Container met `stream_count`, `stream_count_direct_play`, `stream_count_direct_stream`,
`stream_count_transcode`, `lan_bandwidth`, `wan_bandwidth`, `total_bandwidth` en `sessions`.
Een sessie is zeer breed: codecs, bitrates, `transcode_decision`, speler, voortgang, en ook
`ip_address` en `user`.

### `get_home_stats`: populair op je server

`home_stats.json`

Acht blokken: `popular_movies`, `popular_tv`, `last_watched`, `top_users`, `top_platforms`,
`most_concurrent`, `top_movies`, `top_tv`. Parameters `time_range`, `stats_count`, `stats_type`
(`plays` of `duration`), `stat_id` voor één blok, plus `section_id` en `user_id`.

Rijen van `popular_movies` dragen `title`, `year`, `rating_key`, `users_watched`, `total_plays`,
`last_play`, `thumb`, `art`, `guid`, `section_id`. Met `users_watched` erbij is dit direct
bruikbaar als home-rij.

### `get_user_watch_time_stats`: je eigen geschiedenis, dieper dan Plex

Voor de beheerder in deze set: 3796 rijen in Tautulli tegen wat de PMS zelf nog bewaart.
Geeft totalen over 1, 7 en 30 dagen plus alles (`query_days: 0`).

## Wat dit betekent voor de implementatie

1. **Eén sleutel, dus één plek.** De Tautulli-credential hoort thuis bij wie de server beheert,
   niet op het toestel van elke kijker. Wil je de sociale kant wél aan gedeelde gebruikers
   tonen, dan moet er iets tussen zitten dat alleen de veilige vraag beantwoordt, en niet de
   sleutel doorgeeft.
2. **Avatars komen hiervandaan.** Niet van de PMS, want die geeft ze niet.
3. **"Bekeken" is meetbaar** via `watched_status`, dus er hoeft niets geschat te worden. Gebruik
   `get_item_user_stats` niet als bewijs van uitgekeken hebben.
4. **IP-adressen nooit tonen of cachen.** `get_history` en `get_activity` geven ze, inclusief
   publieke. Ze horen niet in een model, een log of een cache-sleutel.
5. **Tonen dat iemand iets keek is een keuze over andermans gegevens.** De 17 gebruikers hebben
   Tautulli niet zelf ingeschakeld en weten niet dat het meekijkt. Een schakelaar die standaard
   uit staat, plus de mogelijkheid om jezelf te verbergen, hoort bij deze functie.

## De captures opnieuw maken

Het script staat niet in de repo, want het heeft een geldige API-key nodig. De aanroepen zijn
telkens `GET {url}/api/v2?apikey=<key>&cmd=<commando>` met de parameters die hierboven per
onderdeel genoemd staan.
