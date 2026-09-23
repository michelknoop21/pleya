# Netflix-redesign tranche 1 — goedgekeurde specificatie

Michel keurde op 23 september 2026 de vier getoonde tvOS-richtingen goed en benadrukte dat deze vier schermen niet de volledige redesign vormen.

Deze tranche levert:

1. Home behoudt zijn huidige compositie. De hero mag maximaal twaalf unieke, geschikte recente films tonen in plaats van acht. Elk hero-item toont ook expliciet `Bekeken`, `Bezig · <percentage>` of `Niet bekeken` vanuit de gezamenlijke kijkstatus; de CTA-rij blijft op dezelfde plek. Deduplicatie, releasefilter, volgorde, fallback, automatische wissel, focus en telefoon/desktopgedrag blijven behouden. Er komt geen padding met series of Top Picks.
2. Mijn Pleya krijgt onder `Jouw verzameling` zelfstandige ingangen voor Collecties en Afspeellijsten, zoals in de goedgekeurde richting. Elke ingang moet een werkend overzicht openen en bestaande details en acties bereikbaar houden. Plex-collecties blijven bibliotheekgebonden; Jellyfin BoxSets zijn volgens de huidige client serverbreed en worden eenmaal per server getoond. Playlists blijven servergebonden. Plex en Jellyfin moeten eerlijk naast elkaar werken en gedeeltelijke bronfouten mogen resultaten van andere bronnen niet verbergen.
3. Bestaande Mijn Pleya-tegels, voorwaarden, focusherstel en Back-keten blijven intact.

De goedgekeurde richtingen voor Uiterlijk, Home-indeling en Verbinding toevoegen volgen in een volgende tranche. Ook detail, catalogus, speler, Live TV, overige instellingen en nog niet onderzochte vensters blijven open; afronding van deze tranche is geen afronding van de redesign.

Productwijzigingen vereisen gerichte RED→GREEN-tests, `scripts/ci_checks.sh`, toepasselijke regressietests en voor UI/focus passende Pleya Verify-asserties met gelezen compositorbeelden.

## Functiebehoud en vervolg

De mockups in `docs/design-audits/2026-09-23-netflix/` zijn ontwerprichtingen, geen actuele toestand of volledige functielijst. De actuele code, de Pleya Verify-beelden en de bestaande TV-registers bepalen per scherm wat behouden moet blijven.

| Oppervlak | Uitkomst in deze tranche | Nog te bewijzen of te bouwen |
|---|---|---|
| Home-hero | De bestaande compositie, selectie, CTA's, focus en automatische wissel blijven; de bovengrens is twaalf en elke slide krijgt een zichtbare gezamenlijke kijkstatus. | Een echt Plex/Jellyfin-profiel met twaalf geschikte films en alle drie statusvarianten op tvOS vastleggen. De huidige `/v1`-fixture levert daarvoor geen releasedata. |
| Mijn Pleya | Collecties en Afspeellijsten zijn afzonderlijke, op capability gefilterde tegels met eigen route. De bestaande tegels en hun platformvoorwaarden blijven. | Simulatorbeelden met beide bronnen en een hardware-focustest; de huidige fixture kan deze twee ingangen niet vullen. |
| Collecties | Plex per bibliotheek, Jellyfin BoxSets eenmaal per server, met passende broncontext; bestaande collectie-detailroute behoudt paginering, afspelen en acties. Gelijknamige Plex-collecties van verschillende bibliotheken blijven gescheiden. | Detailacties per Plex/Jellyfin-capability op echte bronnen nalopen; uitgesteld TV-mappenpad blijft LIB7-vervolgwerk. |
| Afspeellijsten | Eén verzoek per server, per bron gegroepeerd; bestaande playlist-detailroute behoudt afspelen, shuffle en bewerkacties waar ondersteund. | Destructieve acties en serverrechten op echte bronnen nalopen; geen bediening tonen die de backend niet ondersteunt. |
| Fout, leeg en terugkeer | Laden, lege toestand, brongebonden gedeeltelijke fout, verversen/herproberen en focus op de oorspronkelijke tegel zijn afgedekt in code/tests. | Pleya Verify-journeys met compositorbeelden zodra de fixture of een echt profiel de vereiste brondata biedt. |

Pakket A blijft na deze tranche open voor mappen en de echte-broncontroles hierboven. Pakket B begint met Uiterlijk en Home-indeling: inventariseer iedere bestaande voorkeur, sleutel, default, platformvoorwaarde en picker, bouw de goedgekeurde TV-presentatie rond de bestaande handlers, en verifieer scroll, waardeopslag en focusherstel. Pakket C begint met Verbinding toevoegen: behoud de zes actuele opties en hun verschillende auth-/leen-/map-/Share-flows; eerste start blijft een eigen scherm. Pakketten D–F blijven open voor integraties, ontdekken/detail, afspelen en Live TV. Elk pakket krijgt vóór uitvoering een matrix per bestaand bedieningselement met `behouden`, `verplaatst` of `niet van toepassing`, plus een actuele capture; een mockup alleen kan geen functie schrappen.
