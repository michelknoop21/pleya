# Detailpagina-contracten, gemeten tegen een echt Plex-account

Gemeten op 17 augustus 2026 tegen een eigen Plex Media Server (Plexflix, owned) via
`https://plexflixnetwork.eu:443`, plus `plex.tv` en `community.plex.tv`. Alle calls waren
GET of read-only GraphQL; er is niets naar de server geschreven.

Gesaniteerd: tokens, `accessToken`, e-mailadressen, gebruikersnamen, Plex-accounthashes,
machine-identifiers en bestandspaden. Vormen, veldnamen en waardeformaten staan er precies
zo in als de server ze gaf, want dat is het contract. Pseudoniemen zijn stabiel binnen een
bestand, zodat kruisverwijzingen blijven kloppen.

Zie ook `test/fixtures/watchlist/README.md`: hetzelfde patroon, en dezelfde les dat een
plausibel klinkend endpoint iets anders kan betekenen dan de naam suggereert.

## Wat de meting opleverde

### 1. Ratings dragen hun bron, en er zijn er meer dan we nu tonen

`movie_metadata_plain.json` en `movie_metadata_reviews.json`

De platte attributen die de mappers vandaag lezen zijn er:

```
rating              3.7
audienceRating      5.0
ratingImage         rottentomatoes://image.rating.rotten
audienceRatingImage rottentomatoes://image.rating.spilled
```

Maar er staat ook een `Rating[]` naast, en die is rijker:

```json
[{"image":"imdb://image.rating",                    "value":6.0, "type":"audience"},
 {"image":"rottentomatoes://image.rating.rotten",   "value":3.7, "type":"critic"},
 {"image":"rottentomatoes://image.rating.spilled",  "value":5.0, "type":"audience"},
 {"image":"themoviedb://image.rating",              "value":6.5, "type":"audience"}]
```

`type` is letterlijk `critic` of `audience` en `image` noemt de bron. De platte attributen
dragen alleen de bron die in de bibliotheekinstellingen is gekozen; `Rating[]` draagt ze
allemaal. IMDb en TMDB naast Rotten Tomatoes tonen kost dus geen extra call, alleen een
mapper die dit veld leest. Geen enkele parameter nodig: `Rating[]` komt standaard mee.

Schaal is 0 tot 10, ook voor Rotten Tomatoes. `lib/utils/rating_utils.dart` rekent al
`value * 10` naar een percentage; dat klopt.

### 2. Reviews bestaan, maar alleen voor films

`movie_metadata_reviews.json` (19 reviews) versus `show_metadata_reviews.json` (0)

`?includeReviews=1` voegt precies één veld toe: `Review`. De serie kreeg er nul, met
dezelfde parameter op dezelfde server. Een reviews-sectie op seriedetail heeft dus geen
databron en moet niet gebouwd worden.

Vorm van een review:

```json
{"id":148, "filter":"=148", "tag":"Nell Minow",
 "text":"Death by sequel. Extremely violent sequel.",
 "image":"rottentomatoes://image.review.rotten",
 "link":"http://www.commonsensemedia.org/movie-reviews/2-fast-2-furious",
 "source":"Common Sense Media"}
```

`tag` is de criticus, `source` de publicatie, `image` geeft fresh of rotten, `link` wijst
naar het origineel. `text` is een excerpt: in deze set 42 tot 189 tekens. Niet elke review
heeft een `link`.

### 3. Een afgebroken kijkbeurt levert géén history-rij op

`history_item.json` (3 rijen) versus `history_partial_view.json` (`size: 0`)

Dit was de openstaande twijfel bij "Bekeken door". Gemeten:

- Items in Continue Watching op 19%, 23%, 49%, 51% en 60% hebben **nul** history-rijen.
  `history_partial_view.json` is die van een film op 60%.
- Over 9590 server-brede rijen heeft er **geen enkele** een `viewOffset`. Het veld zit
  niet eens in het antwoord.
- Voor acht bekeken films is het aantal history-rijen van de eigenaar steeds gelijk aan of
  lager dan `viewCount`, nooit hoger.

Een rij ontstaat dus bij een voltooide kijkbeurt, niet bij het starten. Rijen kunnen wél
ontbreken (handmatig op bekeken gezet, of buiten de bewaartermijn), dus history is een
ondergrens van "bekeken", geen bovengrens. `WatchedByRow` overdrijft daarmee niet.

Velden op een rij: `accountID`, `deviceID`, `historyKey`, `key`, `librarySectionID`,
`originallyAvailableAt`, `ratingKey`, `thumb`, `title`, `type`, `viewedAt`, en voor
afleveringen de `grandparent*`- en `parent*`-varianten.

### 4. `/accounts` levert geen avatars

`accounts.json`

23 accounts, en `thumb` is bij **alle** leeg. De avatarcluster in `WatchedByRow` valt dus
altijd terug op initialen. Geen token in `thumb`, dus de ontbrekende `cacheKey` in
`_WatcherAvatar` is nu geen lek; het blijft wel een ontbrekende invariant, want er is niets
dat afdwingt dat het zo blijft.

Wil je echte avatars, dan moeten die uit `plex.tv` komen: zowel `home_users.json` als de
community-API geven wél een avatar-URL, en die is tokenloos.

### 5. `plex.tv/api/v2/friends` bestaat niet meer

Gemeten: **HTTP 410 Gone**. Ook `/api/v2/sharing` geeft 404 en `/api/v2/users` geeft 405.
Alleen `/api/v2/home/users` werkt nog (`home_users.json`), met velden `id`, `uuid`,
`username`, `title`, `friendlyName`, `email`, `thumb`, `admin`, `restricted`, `guest`,
`hasPassword`, `pin`, `protected`, `restrictionProfile`, `subscription`, `updatedAt`.

De vriendenlijst is verhuisd naar de community-API.

### 6. community.plex.tv: bruikbaar, ongedocumenteerd, en in de praktijk leeg

Introspectie is uitgeschakeld (`GraphQL introspection has been disabled`). Het schema is
wél af te leiden uit de foutmeldingen, die per ongeldig veld melden welk type het betreft
en soms een suggestie geven.

Root-queries die bestaan: `user(id: ID!)`, `userV2(user: UserInput!)`,
`activityFeed`, `metadataReviews`, `metadataReviewsV2`.
Bestaan niet: `friends`, `watchlist`, `watchHistory`, `userState`, `metadata`, `search`.

**Vrienden** (`community_friends.json`):

```graphql
{ user(id: "<accountHash>") { friends(first: 10) { nodes { id displayName avatar } } } }
```

Werkt, geeft echte vrienden terug met een tokenloze avatar-URL
(`https://plex.tv/users/<hash>/avatar?t=...`). `displayName` was in deze set leeg.

**Activiteit per titel** is `metadataReviewsV2`. De enige geldige waarde van
`ReviewsListType` is `FRIENDS` (getest: CRITIC, USER, ALL, MEMBER, COMMUNITY en TOMATO
worden allemaal geweigerd). `metadata` is een OneOf-input die precies één sleutel wil:
`{id: "<discover guid tail>"}`.

```graphql
query ($id: ID!) {
  metadataReviewsV2(first: 20, type: FRIENDS, metadata: {id: $id}) {
    nodes {
      __typename
      ... on ActivityWatchReview { id date privacy status hasSpoilers message reaction
        rating userV2 { id username displayName avatar } }
      ... on ActivityWatchRating { id date privacy rating
        userV2 { id username displayName avatar } }
    }
    pageInfo { hasNextPage }
  }
}
```

`nodes` is het union-type `ReviewActivity` met implementaties `Activity`,
`ActivityRating`, `ActivityReview`, `ActivityWatchRating` en `ActivityWatchReview`.
Let op: `rating` is `Int` op de ene en `Int!` op de andere, dus een gedeelde selectie moet
een alias gebruiken of de query faalt op een typeconflict.

**En dan de uitkomst die telt** (`community_metadata_reviews_friends_empty.json`): voor
drie geteste titels kwamen er **nul** nodes terug, HTTP 200. De eigen activiteit in
`activityFeed` staat op `privacy: "PRIVATE"`, en zolang vrienden hun kijkgeschiedenis niet
delen levert deze query niets op.

## Wat dit betekent voor de implementatie

- **Rotten Tomatoes uitbreiden is goedkoop.** `Rating[]` lezen geeft IMDb, TMDB en beide
  RT-scores met bron en type, zonder extra request en zonder gokwerk.
- **Reviews alleen op filmdetail.** Serie-niveau heeft geen data.
- **"Bekeken door" op je eigen server is eerlijk.** History betekent voltooid, niet
  gestart. Wat nog moet: `selfAccountId` niet hardcoden op 1, en avatars uit plex.tv halen
  in plaats van uit `/accounts`, want daar staan ze niet.
- **"Bekeken door" via Plex-vrienden is technisch mogelijk maar praktisch leeg**, en hangt
  aan een ongedocumenteerde API met introspectie uit. Bouw dit niet als hoofdroute. Wil je
  het toch, doe het dan als extra dat verdwijnt zodra de query niets teruggeeft, en accepteer
  dat Plex het contract zonder aankondiging kan wijzigen.

## De captures opnieuw maken

Het script staat niet in de repo, want het heeft een geldig Plex-token nodig. De requests
staan hierboven volledig uitgeschreven; een nieuwe capture is een kwestie van ze herhalen
en dezelfde saniteringsregels toepassen.
