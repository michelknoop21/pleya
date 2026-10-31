# C-05 / S8.3 — webcatalogus en facetten

Lokale clientaansluiting na `7a130c3a`; pakket 5 blijft open. Bestaande bibliotheekroute, API-client, cursorpager, dialoog en chips hergebruikt. Geen protocol- of afhankelijkheidswijziging.

De URL bezit genre, jaar, kijkstatus, kwaliteit en sortering. Alle tien bestaande contractsorteringen zijn beschikbaar achter `filters`; oude servers houden zes keuzes en krijgen geen facetverzoek of nieuwe velden. Niet-ondersteunde of ongeldige filterlinks sturen geen onjuiste catalogusaanvraag en bieden wissen. Een lege filteruitkomst heeft een eigen uitweg. Facettellingen gelden zichtbaar voor de volledige bibliotheek. Onbekende kwaliteit blijft als waarde zichtbaar, maar is niet selecteerbaar via het oudere contract.

De catalogus annuleert vervallen aanvragen en laat oude pagina-antwoorden niet de nieuwe selectie vervangen. Laden wordt direct in de bestaande pager gezet. Echte browsergeschiedenis vond een fout in shallow navigatie: de adresbalk wijzigde, maar de reactieve route niet. Gewone navigatie met focus-/scrollbehoud herstelt dit. De gedeelde dialoog wordt buiten pagina-stapellagen gemonteerd; anders bedekte de mobiele tabbalk Annuleren.

**Bewijs.** Publieke catalogus-/API-/filtertests eerst rood. 40 gerichte bestanden, 519 tests PASS, inclusief bestaande beheer- en dialoogcallers; Sveltecheck 0 fouten/waarschuwingen; productie-webbundel groen. Dialoogtest rood zonder portaal; browser-hit-test rood doordat Annuleren werkelijk onder de tabbalk lag, daarna groen. Vier blijvende browserregressietests (desktop/mobiel) PASS tegen eigen synthetische Go-testdata via de bestaande Vite-proxy. Eerste ronde sloeg te vroeg over vóór route-mount; expliciet op de sorteerbediening wachten geeft vier PASS, geen skips.

Chromium: echte filterverzoeken, tien sorteringen, terug/vooruit, leeg resultaat/wissen en focusherstel. 1920/1440/1280/390/320: axe 0, horizontale overloop 0, annuleerknop via hit-test bereikbaar. Beelden bekeken; mobiele beelden na laagreparatie opnieuw bekeken. Bewijs: `.build/pleya-completion-evidence/web-catalog/proof.json`; logs `/tmp/pleya-completion-web-catalog-*` en `...-web-modal-*`.

Niet gesloten: soortbrede catalogus/landings, overige pakket-5-schermen, NAS/browseracceptatie, onafhankelijke eindreview, CI en release. Geen productie gewijzigd.
