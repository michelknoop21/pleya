# Pleya — Handleiding voor gebruikers

**Versie 2.8.0 · 2 juli 2026**

Pleya is een app om films en series van je eigen Plex- of Jellyfin-server te kijken, in een interface die aanvoelt als een moderne streamingdienst. Deze handleiding beschrijft alles wat je als kijker kunt zien en doen.

---

## Inhoudsopgave

1. [Wat is Pleya?](#1-wat-is-pleya)
2. [De eerste keer starten](#2-de-eerste-keer-starten)
3. [Profielen — "Wie is er aan het kijken?"](#3-profielen--wie-is-er-aan-het-kijken)
4. [Het startscherm (Home)](#4-het-startscherm-home)
5. [Media bladeren](#5-media-bladeren)
6. [De detailpagina van een film of serie](#6-de-detailpagina-van-een-film-of-serie)
7. [De videospeler](#7-de-videospeler)
8. [Downloads en offline kijken](#8-downloads-en-offline-kijken)
9. [Live TV en opnames](#9-live-tv-en-opnames)
10. [Zoeken](#10-zoeken)
11. [Samen Kijken](#11-samen-kijken)
12. [Instellingen](#12-instellingen)
13. [Stap voor stap: van installatie tot eerste film](#13-stap-voor-stap-van-installatie-tot-eerste-film)
14. [Veelgestelde vragen](#14-veelgestelde-vragen)
15. [Problemen oplossen](#15-problemen-oplossen)
16. [Begrippenlijst](#16-begrippenlijst)

---

## 1. Wat is Pleya?

Pleya is een kijk-app voor **Plex** en **Jellyfin**. De app bevat zelf geen films of series: je verbindt hem met een mediaserver (van jezelf, of van iemand die zijn server met je deelt) en kijkt vervolgens alles uit die bibliotheek — thuis of onderweg.

De app werkt op telefoon en tablet (iPhone, iPad, Android), computer (Mac, Windows, Linux) en televisie (Apple TV, Android TV). Overal zie je dezelfde donkere, filmische interface: een groot uitgelicht item bovenaan, rijen met posters, profielen per gezinslid en een rode voortgangsbalk onder alles wat je half hebt gekeken.

Wat je ermee kunt:

- Films en series kijken, hervatten waar je gebleven was
- Per gezinslid een eigen profiel met eigen kijkgeschiedenis
- Afleveringen en films downloaden voor offline (vliegtuig, trein)
- Live TV kijken en programma's opnemen (als je server een tv-tuner heeft)
- Ondertitels zoeken, stylen en synchroniseren
- Samen op afstand synchroon kijken met vrienden (**Samen Kijken**)

---

## 2. De eerste keer starten

### De intro

Bij het opstarten zie je kort het coral **PLEYA**-logo. Tik op het scherm om de animatie over te slaan.

### Verbinden met een server

Zonder server is er niets te kijken, dus de app vraagt eerst om een verbinding. Je hebt twee smaken:

#### Inloggen met Plex

1. Kies **Inloggen met Plex**.
2. Kies hoe je wilt inloggen:
   - **Gebruik browser** — er opent een browservenster op plex.tv waar je inlogt met je Plex-account.
   - **Show QR Code** — scan de QR-code met je telefoon en log daar in. Handig op een televisie.
3. De app wacht tot je het inloggen hebt bevestigd ("Waiting for authentication...").
4. Klaar. Alle servers die met jouw Plex-account zijn gedeeld worden **automatisch toegevoegd**, en Plex Home-gebruikers verschijnen automatisch als profielen.

> Je typt nooit je Plex-wachtwoord in de app zelf — inloggen gebeurt altijd via de officiële Plex-website.

#### Verbinden met Jellyfin

1. Kies **Connect to Jellyfin**.
2. Vul het adres van de server in (bijvoorbeeld `https://jellyfin.voorbeeld.nl`). Meerdere adressen mag, gescheiden door komma's. Staat de server bij jou thuis in het netwerk, dan vindt de app hem vaak vanzelf en kun je hem aantikken.
3. Klik **Server zoeken**. De app controleert het adres en toont de servernaam ter bevestiging.
4. Vul **Gebruikersnaam** en **Wachtwoord** in en kies inloggen.
   - Of gebruik **Quick Connect**: de app toont een code die je invoert in de Jellyfin-website. Geen wachtwoord typen nodig — vooral fijn op een televisie.

### Meerdere servers

Je kunt meerdere servers tegelijk gekoppeld hebben (Plex én Jellyfin door elkaar). De inhoud wordt samengevoegd op het startscherm. Extra servers voeg je later toe via **Instellingen** → verbinding toevoegen.

---

## 3. Profielen — "Wie is er aan het kijken?"

Elk gezinslid krijgt een eigen profiel met eigen kijkgeschiedenis, eigen **Verder kijken**-rij en eigen lijsten.

### Profiel kiezen bij het opstarten

Als er meer dan één profiel is, opent de app met het scherm **Wie is er aan het kijken?** — een raster met avatars. Tik op je profiel en je gaat verder waar jij was gebleven. Onderaan staat een knop om profielen te beheren.

> Wil je dit scherm niet bij elke start? Zet dan de instelling **Ask for profile on app open** uit (zie [Instellingen](#12-instellingen)). De app opent dan met het laatst gebruikte profiel.

### Soorten profielen

| Soort | Waar komt het vandaan? |
|-------|------------------------|
| **Plex Home-profiel** | Wordt automatisch aangemaakt voor elke Home-gebruiker van je Plex-account |
| **Lokaal profiel** | Maak je zelf in de app aan: **Nieuw profiel** → naam invullen → optioneel een pincode |

### Pincode

Een profiel kan worden beveiligd met een **4-cijferige pincode**. Bij het wisselen naar dat profiel vraagt de app de code. Handig om kinderen uit het ouder-profiel te houden.

### Profielen beheren

In het profieloverzicht zie je per profiel de avatar, de naam, een **Actief**-label bij het huidige profiel en een slotje als er een pincode op staat. Per profiel kun je via het menu: beheren, **Verwijderen**, of **Afmelden** (bij Plex-profielen).

---

## 4. Het startscherm (Home)

Na het kiezen van je profiel land je op **Home**: het uithangbord van je eigen bibliotheek.

### Wat je ziet

- **De billboard bovenaan** — een groot, automatisch wisselend uitgelicht item (elke 8 seconden), met titel, omschrijving en knoppen om direct af te spelen. Onderaan zie je bij half-gekeken items een rode voortgangsbalk.
- **Verder kijken** — alles wat je half hebt gekeken, klaar om te hervatten.
- **Volgende** — de volgende aflevering van series waar je in zit.
- **Recent toegevoegd** — nieuw op de server.
- **Top 10-rij** — de populairste titels met grote ranggetallen naast de posters (als je server zo'n lijst aanbiedt).
- Meer rijen met aanbevelingen, genres en collecties, afhankelijk van wat je server aanlevert.

Zweef (desktop) of navigeer naar een rij-titel en klik **Alles weergeven** om de complete rij te openen.

### Het "match"-percentage

Bij het uitgelichte item zie je een groen percentage (bijvoorbeeld *87% match*). Dit is simpelweg de beoordeling van de titel omgerekend naar een percentage — geen persoonlijk algoritme.

### Navigatie

| Apparaat | Navigatie |
|----------|-----------|
| **Telefoon/tablet** | Balk onderaan met tabs: **Home**, **Media**, **Live TV**, **Search**, **Downloads**. Houd **Media** lang ingedrukt om snel een bibliotheek te kiezen. |
| **Computer** | Balk bovenaan met het PLEYA-logo en dezelfde tabs als tekst. |
| **Televisie** | Uitklapbare balk aan de linkerkant, te bedienen met de afstandsbediening. |

De tab **Live TV** verschijnt alleen als je server live-televisie aanbiedt. **Instellingen** vind je op mobiel via het profielmenu; op desktop en TV staat hij in de navigatie.

### Kaarten en het snelmenu

Elke poster ("kaart") reageert op:

- **Tikken/klikken** — opent de detailpagina (of speelt direct af, instelbaar).
- **Zweven met de muis** (computer) — na een korte pauze klapt de kaart uit tot een voorvertoning met ronde knoppen: **Afspelen**, toevoegen aan je lijst, en details openen.
- **Lang indrukken / rechtsklikken** — opent het volledige snelmenu:

| Menu-optie | Wat doet het? |
|------------|---------------|
| **Afspelen** | Start de titel (hervat waar je was) |
| **Afspelen vanaf het begin** | Negeert je kijkpositie |
| **Trailer afspelen** | Speelt de trailer (indien beschikbaar) |
| **Markeer als gekeken** / **Markeer als ongekeken** | Zet het vinkje handmatig |
| **Verwijder uit Doorgaan met kijken** | Haalt het item uit je Verder kijken-rij |
| **Details bekijken** | Opent de detailpagina |
| **Toevoegen aan...** | Zet de titel in een afspeellijst of collectie |
| **Download** | Downloadt voor offline kijken |
| **Play in External Player** | Opent de titel in een externe speler (bijv. VLC) |

---

## 5. Media bladeren

De tab **Media** toont één bibliotheek van je server (bijvoorbeeld "Films" of "Series"), met vier tabbladen:

| Tabblad | Inhoud |
|---------|--------|
| **Recommended** | Aanbevolen selecties uit deze bibliotheek |
| **Browse** | Alles, als raster of lijst |
| **Collections** | Collecties (bijv. complete filmreeksen) |
| **Playlists** | Afspeellijsten |

### Handig bij het bladeren

- **Filteren** — op genre, jaar, ongekeken, resolutie en meer. Met **Clear All** wis je alle filters.
- **Sorteren** — kies waarop gesorteerd wordt en of het oplopend of aflopend is.
- **Letterbalk** — spring direct naar een beginletter in lange lijsten.
- **Wisselen van bibliotheek** — op mobiel: houd de **Media**-tab lang ingedrukt; op TV: kies de bibliotheek in de zijbalk.

---

## 6. De detailpagina van een film of serie

Tik op een titel en je ziet de detailpagina: groot achtergrondbeeld, titel(logo), beoordeling, jaar en samenvatting (**Overzicht**), gevolgd door — bij series — de seizoenen en afleveringen, en verder **Acteurs**, **Trailers & Extra's** en **Meer zoals dit**.

### De actieknoppen

| Knop | Wat doet het? |
|------|---------------|
| **Afspelen** / **Hervatten** | Start het afspelen. Bij series start automatisch de juiste (volgende) aflevering. |
| **Trailer** | Speelt de trailer |
| **Shuffle** | Speelt afleveringen in willekeurige volgorde (series) |
| **Download** | Downloadt de titel; verandert tijdens het downloaden in een voortgangsindicator |
| **Gekeken-vinkje** | Markeert als gekeken of ongekeken |
| **⋮ (meer)** | Opent het volledige snelmenu |

Op een smal scherm verhuizen sommige knoppen naar het **⋮**-menu.

### Afleveringen

Elke aflevering toont een miniatuur, nummer, titel, korte omschrijving en een rode voortgangsbalk als je hem half hebt gekeken. Tik om af te spelen of details te zien (instelbaar). Wissel van seizoen via de seizoenskiezer.

> Tip: wil je geen plot verklappen? Zet **Hide Spoilers for Unwatched Episodes** aan in de instellingen — miniaturen en omschrijvingen van ongekeken afleveringen worden dan vervaagd.

---

## 7. De videospeler

Tijdens het afspelen tik of beweeg je om de bediening te tonen.

### Basisbediening

- **Afspelen / pauzeren**, vooruit en achteruit springen (spring-duur instelbaar)
- **Tijdbalk** met hoofdstukmarkeringen; sleep om te spoelen, met voorbeeldminiaturen
- **Volgende / vorige aflevering** en **Hoofdstukken**
- **Wachtrij** — bekijk en beheer wat hierna komt

### Audio en ondertitels

Open het sporenmenu voor:

- **Audio** — wissel van taal of geluidsspoor
- **Ondertitels** — kies een spoor, of zet uit
- **Ondertitels zoeken** — zoek en download online ondertitels (alleen bij Plex-servers)

De app onthoudt je taalkeuzes en past ze automatisch toe op volgende afleveringen.

### Instellingen tijdens het afspelen

Via het instellingen-icoon in de speler:

| Optie | Wat doet het? |
|-------|---------------|
| **Playback Speed** | Sneller of langzamer afspelen |
| **Sleep Timer** | Stopt automatisch na een tijd of aan het einde van de video |
| **Audio Sync** / **Subtitle Sync** | Verschuif geluid of ondertitels als ze niet gelijk lopen |
| **Version & Quality** | Kies een andere bestandsversie of lagere kwaliteit (bij traag internet) |
| **Zoom / beeldvulling** | Letterbox, scherm vullen of uitrekken |
| **Auto-Play Next** | Volgende aflevering automatisch starten |

### Slim overslaan

- **Skip intro** en **Skip credits**-knoppen verschijnen bij het begin en einde (waar de server ze kent). In de instellingen kun je dit automatisch laten gebeuren.
- Kijk je lang achter elkaar, dan vraagt de app af en toe **"Still watching?"** — kies **Continue** om verder te gaan.

### Gebaren (telefoon/tablet)

- **Dubbeltik links/rechts** op het beeld: terug- of vooruitspringen
- **Vegen aan de linkerrand**: helderheid; **rechterrand**: volume
- **Schermvergrendeling**: knop die alle bediening blokkeert tegen per-ongeluk-tikken
- **Picture-in-Picture**: kijk verder in een klein venster terwijl je andere apps gebruikt (telefoon en Mac)

---

## 8. Downloads en offline kijken

Films en afleveringen kun je op je apparaat opslaan om zonder internet te kijken.

### Downloaden

1. Open het snelmenu van een titel (lang indrukken) of de detailpagina.
2. Kies **Download**.
3. Bij series kies je: **alle afleveringen** of **alleen ongekeken**, en of specials meegaan.
4. Volg de voortgang op de detailknop (percentage) of in de tab **Downloads**.

### De Downloads-tab

Drie tabbladen: **Manage** (alles beheren), **TV Shows** en **Movies**. Acties: **Alles pauzeren**, **Alles hervatten**, **Alles verwijderen**, en per item verwijderen of opnieuw proberen.

Ben je offline, dan opent de app automatisch op deze tab en kun je alles wat gedownload is gewoon kijken. Je kijkvoortgang wordt gesynchroniseerd zodra je weer online bent.

### Synchronisatie-regels

Voor een serie kun je een doorlopende regel instellen, zoals **Gesynchroniseerd houden** of "houd 3 ongekeken afleveringen klaar". Nieuwe afleveringen worden dan automatisch gedownload en gekeken afleveringen kunnen automatisch worden opgeruimd. Regels beheer je via **Sync rules** in de Downloads-tab.

### Download-instellingen

- **Download on WiFi only** — voorkomt downloaden via je databundel
- **Auto-remove watched downloads** — ruimt gekeken items automatisch op
- **Downloadlocatie** — standaard in de app, of een eigen map (computer)

---

## 9. Live TV en opnames

Heeft je server een tv-tuner met gids, dan verschijnt de tab **Live TV**.

### Kijken

- **Gids** — het programmaoverzicht per zender en tijdvak (Nu, Ochtend, Middag, Avond, Late avond; Vandaag/Morgen)
- **Nu op TV** — wat er op dit moment draait
- **Favorieten** — markeer je vaste zenders en zet ze in je eigen volgorde

Tik op een programma voor de detailkaart met **Live kijken**, of — bij een al begonnen programma — **Kijk vanaf het begin**. Tijdens live kijken kun je terugspoelen en met **Go to Live** weer naar het live-punt springen.

### Opnemen

- **Opnemen** — neem één uitzending op
- **Serie opnemen** — neem automatisch elke aflevering op
- **Opnames** — je opgenomen programma's, plus geplande opnames en opnameregels

> Opnemen en opname-instellingen vereisen een beheerdersaccount op de server.

---

## 10. Zoeken

Open de tab **Search** en typ in het zoekveld (*"Zoek films, series, muziek..."*). Je zoekt in één keer door alle gekoppelde servers — op titel, acteur of trefwoord. Geen resultaat? Probeer een ander trefwoord of controleer de spelling.

Op de computer open je zoeken snel met **Cmd+F** (Mac) of **Ctrl+F** (Windows/Linux).

---

## 11. Samen Kijken

Met **Samen Kijken** kijk je synchroon met anderen op afstand: pauzeert er één, dan pauzeert het bij iedereen.

1. Open **Samen Kijken** (icoon op het startscherm).
2. Kies **Sessie Maken** — je krijgt een code van 5 tekens.
3. Deel de code. De ander kiest **Sessie Deelnemen** en voert de code in.
4. Start de film. Afspelen, pauzeren en spoelen loopt bij iedereen gelijk.

De maker van de sessie bepaalt of alleen de host mag bedienen (**Host Only**) of iedereen (**Anyone**). Deelnemers zien elkaars aanwezigheid. Verlaten kan altijd via **Leave Session**; de host kan de sessie beëindigen met **End Session**.

> Iedere deelnemer heeft zelf toegang tot dezelfde titel nodig (dezelfde server of een eigen kopie).

---

## 12. Instellingen

Open **Instellingen** via de navigatie (desktop/TV) of het profielmenu (mobiel).

### Uiterlijk

| Instelling | Wat doet het? |
|------------|---------------|
| **Thema** | Systeem / Licht / Donker / **OLED** (puur zwart — zuiniger en mooier op OLED-schermen). Donker is de standaard. |
| **Taal** | De taal van de app |
| **Toon hoofdsectie** | De grote billboard bovenaan Home aan/uit |
| **Kaarten uitklappen bij hover** | De uitklap-voorvertoning op de computer aan/uit |
| **Library Density** / **View Mode** | Compacter of ruimer raster; raster of lijst |
| **Episode Poster Style** | Miniatuur, serieposter of seizoensposter bij afleveringen |
| **Hide Spoilers for Unwatched Episodes** | Vervaagt beeld en tekst van ongekeken afleveringen |
| **Show Navigation Bar Labels** | Tekst onder de navigatie-iconen aan/uit |

### Video afspelen

| Instelling | Wat doet het? |
|------------|---------------|
| **Speler backend** | ExoPlayer (aanbevolen) of mpv |
| **Default Quality** | Maximale streamkwaliteit — lager bespaart data |
| **Hardware Decoding** | Vloeiender afspelen; vrijwel altijd aan laten |
| **Auto Skip Intro / Credits** | Intro's en aftitelingen automatisch overslaan |
| **Small/Large Skip Duration** | Hoe ver de spring-knoppen springen |
| **Rewind on Resume** | Spoelt bij hervatten een paar seconden terug |
| **Subtitle Styling** | Lettergrootte, kleur, rand en achtergrond van ondertitels |
| **Remember track selections** | Onthoudt je taalkeuzes per serie/film |

### Gedrag en opstarten

| Instelling | Wat doet het? |
|------------|---------------|
| **Ask for profile on app open** | Het "Wie is er aan het kijken?"-scherm bij elke start |
| **Startup Section** | Met welke tab de app opent |
| **Continue Watching Action** / **Episode Action** | Tikken = direct afspelen of eerst details |
| **TV-modus forceren** | Dwingt de TV-interface af (na herstart) |

### Koppelingen

- **Trakt, MyAnimeList, AniList, Simkl** — kijkgeschiedenis automatisch bijhouden op deze diensten
- **Discord Rich Presence** (computer) — toont in Discord wat je kijkt
- **Companion Remote** — bedien de app op je TV of computer vanaf je telefoon (zelfde netwerk)

### Beheer

- **Instellingen exporteren / importeren** — neem je configuratie mee naar een ander apparaat
- **Controleer op updates**, **Cache wissen**, **Instellingen resetten**
- **Over** — versie-informatie en licenties

---

## 13. Stap voor stap: van installatie tot eerste film

1. Installeer en open Pleya.
2. Kies **Inloggen met Plex** en log in via de browser (of kies **Connect to Jellyfin** en vul serveradres + inloggegevens in).
3. Wacht tot je servers zijn toegevoegd.
4. Kies of maak je profiel op het **Wie is er aan het kijken?**-scherm.
5. Je landt op **Home**. Blader door de rijen of ga naar **Media** voor de volledige bibliotheek.
6. Tik op een film → **Afspelen**.
7. Stel tijdens het kijken je **ondertitels** en **audio** in — die keuze wordt onthouden.
8. Stop gerust halverwege: de film staat de volgende keer klaar onder **Verder kijken**, en het opstartitem toont **Hervatten**.

Checklist voor onderweg: open van tevoren de detailpagina van wat je wilt kijken → **Download** → controleer in **Downloads** dat alles op 100% staat.

---

## 14. Veelgestelde vragen

**Zit er zelf inhoud in de app?**
Nee. De app speelt alleen af wat er op jouw (of een gedeelde) Plex- of Jellyfin-server staat.

**Kan ik Plex én Jellyfin tegelijk gebruiken?**
Ja. Voeg beide toe; de inhoud wordt samengevoegd op het startscherm.

**Waarom staat er een percentage zoals "87% match" bij een titel?**
Dat is de beoordeling van de titel als percentage — geen persoonlijke aanbeveling.

**Kijkt iedereen in huis via hetzelfde profiel?**
Alleen als je dat zo laat. Maak per persoon een profiel; dan heeft ieder zijn eigen Verder kijken-rij en kijkgeschiedenis.

**Hoe voorkom ik dat mijn kinderen mijn profiel gebruiken?**
Zet een 4-cijferige pincode op je profiel.

**Waarom zie ik de tab Live TV niet?**
Die verschijnt alleen als een gekoppelde server een tv-tuner/DVR heeft.

**Kan ik casten naar een Chromecast?**
Nee. Installeer de app in plaats daarvan direct op je TV (Apple TV / Android TV), of gebruik **Companion Remote** om de TV-app vanaf je telefoon te bedienen.

**Werken downloads op al mijn apparaten?**
Downloads staan per apparaat. Download dus op het apparaat waarop je offline wilt kijken.

**Het beeld is soms wazig of blokkerig — hoe krijg ik betere kwaliteit?**
Zet **Default Quality** hoger (of op *Original*). Let op: hogere kwaliteit vraagt meer bandbreedte van jou én de server.

**Kan ik de intro van een serie automatisch overslaan?**
Ja: **Auto Skip Intro** aanzetten in de instellingen. Er verschijnt anders altijd een knop.

**De app staat in het Engels — hoe zet ik hem in het Nederlands?**
**Instellingen → Uiterlijk → Taal**.

**Ondertitels lopen niet gelijk met het beeld.**
Open in de speler het instellingenmenu → **Subtitle Sync** en verschuif tot het klopt.

**Kan ik zien wat er nieuw is op de server?**
Ja, de rij **Recent toegevoegd** op Home.

**Wat gebeurt er als twee mensen tegelijk kijken?**
Dat kan gewoon; de server bepaalt hoeveel gelijktijdige streams hij aankan.

---

## 15. Problemen oplossen

### "Unable to connect to media server"
**Oorzaak:** de server is uit, onbereikbaar of je internet hapert.
**Oplossing:** controleer of de server draait en of je internet werkt. In de app verschijnt een balk met een **Reconnect**-knop — tik erop zodra de server terug is. Gedownloade titels blijven intussen gewoon afspeelbaar.

### "Invalid username or password" (Jellyfin)
**Oorzaak:** verkeerde inloggegevens.
**Oplossing:** controleer gebruikersnaam en wachtwoord (let op hoofdletters). Weet je het wachtwoord niet meer, vraag de serverbeheerder om het te resetten. Of gebruik **Quick Connect** zodat je niets hoeft te typen.

### "Server did not respond in time" bij het toevoegen van Jellyfin
**Oorzaak:** het adres klopt niet of de server is van buitenaf niet bereikbaar.
**Oplossing:** controleer het adres inclusief `https://` en eventueel poortnummer (bijv. `:8096`). Test het adres in een browser op hetzelfde apparaat.

### Inloggen met Plex blijft hangen ("Waiting for authentication...")
**Oorzaak:** het inloggen op plex.tv is niet afgerond; na ±2 minuten verloopt de aanvraag ("PIN expired").
**Oplossing:** begin opnieuw en rond het inloggen in de browser direct af. Op een TV: gebruik de QR-code en log in via je telefoon.

### Een film start niet of valt weg ("Playback failed")
**Oorzaak:** de server kan het bestand niet (snel genoeg) leveren of omzetten.
**Oplossing:** probeer het opnieuw. Blijft het misgaan: kies in de speler **Version & Quality** en zet de kwaliteit lager. Meldt de app een serverfout over een bandbreedte- of transcodeerlimiet, dan moet de servereigenaar die limiet verruimen.

### Haperend of schokkerig beeld
**Oorzaak:** te hoge kwaliteit voor je verbinding, of zwaar bestand voor je apparaat.
**Oplossing:** verlaag **Default Quality**; controleer dat **Hardware Decoding** aan staat. Op oudere apparaten helpt het wisselen van **Speler backend** (ExoPlayer ↔ mpv).

### Geen geluid of verkeerde taal
**Oorzaak:** verkeerd audiospoor gekozen.
**Oplossing:** open in de speler het sporenmenu → **Audio** en kies het juiste spoor. De app onthoudt die keuze voor volgende afleveringen.

### Een download blijft hangen of mislukt
**Oorzaak:** verbinding onderbroken, of downloaden staat beperkt tot wifi.
**Oplossing:** open **Downloads** → **Manage** en kies opnieuw proberen of **Alles hervatten**. Zit je op mobiele data, controleer dan de instelling **Download on WiFi only**.

### Mijn kijkvoortgang klopt niet op een ander apparaat
**Oorzaak:** de voortgang staat op de server, maar je keek offline of onder een ander profiel.
**Oplossing:** ga online zodat de app kan synchroniseren, en controleer dat je op beide apparaten hetzelfde profiel gebruikt.

### Het profielscherm verschijnt niet meer bij het opstarten
**Oorzaak:** de instelling staat uit.
**Oplossing:** zet **Ask for profile on app open** aan in de instellingen.

### "No channels available" bij Live TV
**Oorzaak:** geen tuner/DVR gekoppeld aan de server, of de gids is verlopen.
**Oplossing:** tik op **Reload Guide**. Blijft het leeg, dan moet de serverbeheerder de tuner en gids op de server controleren.

### De app doet raar na een update
**Oplossing:** probeer eerst **Cache wissen** (Instellingen → Advanced). Helpt dat niet, dan **Instellingen resetten** — exporteer eventueel eerst je instellingen via **Instellingen exporteren**.

**Kom je er niet uit?** Neem contact op met de beheerder van je mediaserver — die kan in de serverlogboeken zien wat er misgaat. Vermeld wat je deed, wat je zag (foutmelding) en op welk apparaat.

---

## 16. Begrippenlijst

| Term | Betekenis |
|------|-----------|
| **Plex / Jellyfin** | Software waarmee je thuis je eigen "streamingdienst" draait; Pleya is de kijk-app die daarmee verbindt |
| **Server** | De computer/NAS waarop Plex of Jellyfin draait en waar de media staan |
| **Bibliotheek** | Een verzameling op de server, zoals "Films" of "Series" (tab **Media**) |
| **Hub / rij** | Een horizontale rij titels op het startscherm (bijv. Verder kijken) |
| **Billboard / hoofdsectie** | Het grote uitgelichte item bovenaan Home |
| **Profiel** | Persoonlijke omgeving per gezinslid, met eigen kijkgeschiedenis |
| **Plex Home** | Plex-functie voor gezinsaccounts; die gebruikers worden hier profielen |
| **Quick Connect** | Jellyfin-inlogmethode met een code in plaats van een wachtwoord |
| **Verder kijken** | De rij met alles wat je half hebt gekeken |
| **Match %** | De beoordeling van een titel omgerekend naar een percentage |
| **Direct play / transcoderen** | De server stuurt het bestand onbewerkt door (direct play) of zet het live om naar een lager formaat (transcoderen) als dat nodig is |
| **Versie** | Sommige titels staan in meerdere kwaliteiten op de server (bijv. 4K en 1080p); je kunt kiezen welke je afspeelt |
| **OLED-thema** | Puur zwart thema, ideaal voor OLED-schermen |
| **Picture-in-Picture (PiP)** | Verder kijken in een klein zwevend venster |
| **Sleep Timer** | Stopt het afspelen automatisch na een ingestelde tijd |
| **Sync-regel** | Automatische download-afspraak per serie (bijv. altijd 3 ongekeken afleveringen klaar) |
| **DVR** | Digitale videorecorder: live TV opnemen via de server |
| **EPG / Gids** | Het elektronische programmaoverzicht van Live TV |
| **Samen Kijken** | Synchroon kijken met anderen op afstand via een sessiecode |
| **Companion Remote** | Je telefoon als afstandsbediening voor de app op TV of computer |
| **Trakt / MAL / AniList / Simkl** | Externe diensten die je kijkgeschiedenis bijhouden |
| **Quick Connect-code / QR-code** | Manieren om zonder wachtwoord typen in te loggen, vooral op TV |
