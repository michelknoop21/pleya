# Rapport: filmdetail, serie en seizoen op Apple TV

Film, serie, seizoen en Meer acties volgen de referenties van 30 oktober 2026. De pagina scrolt, de serie heeft tabs, Discussies komen van Trakt en de activiteitsregel zegt per backend wie keek. Besluit: DEC-171, serverkant DEC-169, roadmapregel A-25.

## Waar het beeld afwijkt en waarom

1. Geen zijbalk: de inklapbare topnavigatie blijft, besluit Michel.
2. Geen soundtrack: geen Tracks-sectie en geen pagina van beeld 11, de onderkant van beeld 10 wijkt daardoor af.
3. Een lange audiowaarde in Meer acties wordt afgekapt.
4. Geen rij More Ways to Watch: daar is in Pleya geen bron voor.
5. Avatars zijn initialen, want het protocol kent geen avatar.
6. Reacties op een seizoen staan op tab Serie, niet op de seizoentab.
7. Discussies verschijnen pas als je onder de hero komt, zodat Trakt niets hoort van een pagina die je alleen opent.
8. Pleya Server heeft geen Add to List en geen Add to Playlist / Collection. Reden in DEC-171.

## Bewijs

Simulator-PASS voor `tvos.detail.movie`, `series`, `season`, `more-actions` en `tvos.settings.activity-sharing`, paden in `MANIFEST.md`. Widgettests en `scripts/ci_checks.sh` groen. Plex, Jellyfin en Emby zijn met widgettests bewezen, niet in de simulator: Verify kent alleen `PleyaFakeServer`. Dit is geen hardwarebewijs.

## Niet bewezen

Prestaties van de vaste achtergrond tijdens scrollen op een echte Apple TV. Add to Playlist / Collection tegen een echte Jellyfin- of Emby-server. De activiteitsregel en de instelling tegen een echte Pleya Server: de NAS draait het endpoint nog niet en toont tot de deploy alleen je eigen regel.

## Apple TV-checklist voor Michel

1. Open een film die je half keek: pil Hervatten met ring, resterende tijd, regel Activiteit van jou, labels rechts op één hoogte.
2. Druk DOWN door alle secties en UP terug: de pagina stopt op offset 0 op de actierij en de achtergrond blijft staan. Let op haperen.
3. Open een serie: RIGHT over de tabs, witte pil onder de focus, omlijnde pil als de focus in de pagina staat. DOWN naar acties, seizoenen, cast, discussies.
4. Op een seizoentab: de kaarten, A1 met vinkje, de naamregel volgt de ring, de pagina scrolt niet. Menu gaat terug naar de poster, nogmaals Menu sluit.
5. Open de ⋮: Audiostream, Ondertitels, Toevoegen aan kijklijst, Toevoegen aan afspeellijst / collectie op Plex. Kies een spoor en controleer de rij; Menu zet de focus terug op de ⋮.
6. Voeg op Plex en op Jellyfin een film toe aan een afspeellijst en aan een collectie, en controleer dat hij daar staat.
7. Controleer Discussies op een film met reacties, de volle tekst na Select, en het wegblijven op een kinderprofiel en met de instelling uit.
8. Na de NAS-deploy: twee accounts, beide kijken een film; de regel noemt beiden. Zet Mijn activiteit delen uit op het ene account: het andere ziet hem niet meer, zijn eigen regel blijft.
9. Intro overslaan met realtime gelijktrekken aan, daarna met de instelling uit: klinkt het eerste moment luider? Regel A25-INTRO-LOUDNORM.
