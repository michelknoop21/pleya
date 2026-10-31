# Filmdetail, serie en seizoen op Apple TV: inventaris van functies

Stand van branch `feat/tvos-detail-northstar`. Route: `MediaDetailScreen` op TV, pagina `TvDetailPage` (`lib/screens/media_detail/tv/`). Elke rij zegt of de functie de herbouw heeft overleefd. iPhone, iPad en desktop houden hun eigen weergave; wat daar verandert staat onderaan.

| Functie | Voor de herbouw | Nu |
|---|---|---|
| Pagina | één scherm dat niet scrolt, hubs schuiven in `TvBrowseRail` | verticale pagina met vaste achtergrond, secties laden bij naderen, een lege sectie verschijnt niet |
| Afspelen | knop met label | witte pil Hervatten met ring en resterende tijd; zonder voortgang Afspelen |
| Ronde acties | rij naast de speelknop | zelfde model (`detail_actions.dart`), plus de ⋮ als laatste |
| Trailer | knop in de rij | rij in Meer acties, zodat niets verdwijnt |
| Aanvraag (Seerr) | knop in de rij | rij in Meer acties |
| Sporen kiezen | alleen in de speler | rij Audio en Ondertitels in Meer acties, via `TrackPreferenceStore` zoals de telefoon |
| Versie, bestandsinfo, beoordelen, gekeken, shuffle, vanaf begin | contextmenu | rijen in Meer acties, zelfde definitie (`menuActions`, `runMenuAction`) |
| Beheren (bewerken, match, verwijderen) | contextmenu | groep Beheren in Meer acties, alleen met rechten |
| Bron wisselen (unified) | bronregel onder de acties | bronregel blijft, plus rij Bron in Meer acties |
| Technische labels | geen | rechts naast de activiteit, uit `media_quality_labels.dart` en de sporenvoorspelling |
| Scores | alleen Plex-velden | `DetailScoreRow`-bron: IMDb, Rotten Tomatoes, publiek, TMDB, wat de backend levert |
| Now Watching en Stats | weggeklipt in de vaste band | de hero groeit mee |
| Wie keek | Plex, alleen eigenaar | Plex ongewijzigd, Pleya Server onder de capability, eigen regel op Jellyfin, Emby en Pleya Server |
| Cast & Crew | rij | rij met ronde portretten, initialen zonder foto |
| Reviews | Plex, op film | sectie Ratings & Reviews, zelfde bron |
| Discussies | bestond niet | sectie uit Trakt-reacties, Select opent de volle tekst in een paneel |
| Trailers & Extras, collectie, Meer met acteur | rijen | secties op de pagina, bij naderen geladen |
| Seizoenen | chips boven de afleveringen | tabs Serie en Season N, seizoensposters op tab Serie |
| Afleveringen | lijst | brede kaarten op de seizoentab, seizoenkaart vooraan |
| Deep-link naar aflevering | seizoenschip en lijst | opent de seizoentab op die aflevering, ook voorbij de eerste pagina |
| Episode Action | instelling | blijft: play speelt af, details opent de eigen pagina van de aflevering |
| Terugkeer uit acteur of aflevering | focus op de pagina | `TvFocusRestoreHost` zet de ring terug op de kaart, per seizoen de laatste kaart |
| Menu | sluit de pagina | seizoen terug naar de poster, dan de pagina; een pagina die op een seizoen opende sluit meteen |
| Offline | detail met kijkstatus | ongewijzigd; de activiteitsregel leest dan niets |

## Nieuwe instellingen

| Instelling | Waar | Standaard |
|---|---|---|
| Discussies van Trakt tonen | Geavanceerd, Privacy, alleen op TV en niet op een kinderprofiel | aan |
| Mijn activiteit delen | TV: Geavanceerd, Privacy. Elders: Geavanceerd, Privacy. Alleen met `capabilities.item_activity` | aan, restricted uit; de waarde staat op de server |

## Buiten Apple TV geraakt

Het iPhone-activiteitenkaartje toont de namen van een Pleya Server en zegt daar "Activity by". De eigen regel uit de kijkstatus staat alleen op TV: Jellyfin op iPhone houdt dus geen kaartje. Add to Playlist / Collection staat op alle platforms op Jellyfin en Emby, want de rij komt uit het gedeelde mediamenu.
