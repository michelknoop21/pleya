# Pleya Netflix-redesign — tranche 2

Basis: `47a1663f` (tranche 1). Richting: de door Michel goedgekeurde `docs/design-audits/2026-09-23-netflix/02-uiterlijk`, `03-home-indeling` en `04-verbinding`; deze beelden zijn voorstellen, geen actuele screenshots. De nulmeting komt uit Pleya Verify-bundels `tvos-ux23-settings-depth-1790184222009`, `tvos-ux23-settings-followup-1790184518723` en `tvos-ux23-forms-1790184701187`. NLX2 en NLX3 staan in `docs/tvos-fysieke-correctieronde.md`.

## Volgorde

1. **Simulator betrouwbaar maken.** Gebruik een eigen simulator-UDID voor Pleya Verify. De eerdere `Connection reset by peer` kwam tijdens een herinstallatie van dezelfde verify-bundle door een andere run op hetzelfde toestel. Corrigeer de verouderde `tvos.my-pleya.section-settings`-navigatie op basis van de gemeten focus, valideer, herhaal en lees screenshots/UI-tree. Bewaar de echte Back-focus als regressie-eis.
2. **Home-indeling.** Het actuele scherm toont dezelfde `Recent toegevoegd / Zolder`-tekst voor films en series, en onbegrensde rijen met bediening rechts tegen de rand. Geef elke rij zichtbare media-/broncontext uit het bestaande `MediaHub`-model, houd vaste Hero/Verder kijken expliciet buiten de bewerkbare lijst, en gebruik TV-veilige kaartmarges en focusstaten. Verplaats, toon/verberg en bewaarde rij-ID's blijven ongewijzigd. Begin met een falende widgetcontrole voor de dubbele labels en bediening; daarna Pleya Verify met compositorbeeld, volgorde en Back.
3. **Uiterlijk.** Maak eerst een pariteitslijst per bestaande `SettingsService`-voorkeur en platformvoorwaarde. Bouw een TV-eigen categoriepaneel voor Weergave, Home, Navigatie en Inhoud met compacte waarderijen, zichtbare focus en bestaande handlers. Behoud taalherstart, motion-herstart en alle segment-/slider-/switchwaarden; desktop en mobiel blijven op hun bestaande presentatie. Leg focuswissel, instellingwijziging en terugkeer vast in widgettests en Pleya Verify.
4. **Verbinding toevoegen.** Vergelijk de huidige route met mockup 04 en leg alle zes ingangen vast: Plex, Jellyfin, Pleya Server, lokale map, Pleya Share en lenen uit profiel. Pas alleen de TV-presentatie aan rond bestaande routes en authformulieren. Test alle zichtbare routes, terugkeer en fout-/annuleerpad; live accountkoppeling blijft aparte controle.
5. **Overige vensters.** Loop pakketten B–F uit de designaudit af met `surface-inventory.md` en `controls-inventory.tsv` als zoekhulp. Een pakket krijgt pas eindstatus nadat iedere bestaande actie en platformvariant behouden, bewust verplaatst of niet van toepassing is verklaard. Open hardwarepunten blijven open tot een echte Apple TV-run.

## Uiterlijk: te behouden bedieningen

De bestaande eigenaar is `AppearanceSettingsScreen`; de TV-variant mag deze voorkeurswaarden en handlers niet dupliceren in een tweede opslaglaag. Dit is de code-nulmeting voor stap 3:

| Categorie | Altijd / tvOS | Voorwaardelijk buiten tvOS |
| --- | --- | --- |
| Weergave | Thema (4 standen), taal met herstart, bibliotheekdichtheid, weergavemodus, afleveringsposter, volledige TV-kaart, focusgloed, titels onder posters, verminderde beweging met herstart, afleveringsnummer | Android visuele effecten met herstart; seizoensposters op niet-TV |
| Home | TV-hero-logo, automatische hero-wissel, persoonlijke aanbevelingen, Verder kijken-actie, globale hubs, servernaam op rijen | Hero tonen op niet-TV; hoveruitbreiding op desktop |
| Navigatie | Startpagina, zijbalk openhouden, bibliotheken per server groeperen, teller niet-bekeken | Android TV-modus met herstart; navigatielabels zonder zijbalk |
| Venster | Geen tvOS-instellingen | Volledig scherm starten en bij sluiten van speler verlaten op desktop-OS |
| Inhoud | Live TV-favorieten als standaard, spoilers verbergen, aflevering-actie, prestatie-overlay automatisch verbergen; profielkeuze alleen bij meerdere profielen | Dezelfde voorwaarden op andere platforms |

`HomeLayoutScreen` bewaart de huidige `homeRowId`-sleutels en `HomeLayoutProvider`-opslag. De zichtbare context wordt uit `MediaHub.type` en `serverName` gehaald; geen rij wordt op titel alleen geïdentificeerd. De TV-presentatie gebruikt `TvPageSurface` voor marges en titel, terwijl pointerplatforms hun drag-to-reorder-route houden.

Per codewijziging: een negatieve controle op de oude implementatie, gerichte tests, `scripts/ci_checks.sh`, daarna relevante Pleya Verify-asserties en gelezen compositorbeelden. Een scenario met verouderde choreografie mag worden gecorrigeerd op meetbare focus; productasserties worden niet afgezwakt. Bewijsbundels blijven onder `.build/`, buiten Git.
