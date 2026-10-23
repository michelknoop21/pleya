# S7: routes en staten naast de northstar

Opgenomen op 23 oktober 2026 tegen de e2e-stack (`scripts/e2e-stack.sh`, bundel in de binary),
donker thema, Nederlands. Bron: `pleya_web/scripts/routes-shots.ts --locale nl`. De galerij komt
uit `vite dev` met `pw screenshot --full-page`, omdat `/dev/primitives` in de bundel niet bestaat.

## Wat er ligt

| Bestand | Bewijst |
| --- | --- |
| `<scherm>@{1920,1440,1280,390,320}-nl.jpg` | elke route en staat op de vaste breedtes, één scherm hoog |
| `<scherm>@<w>-nl-app.jpg` | dezelfde pagina op een breedte van de northstar, vanaf 900 als hele pagina |
| `<scherm>-vs-northstar@<w>.jpg` | links de app, rechts het goedgekeurde beeld |
| `galerij@{1920,1440,1280,390,320}-nl.jpg` | alle primitieven in hun staten, hele pagina |

Schermen: 01 Home, 05 een filmbibliotheek, 06 zoeken met treffers, 07 zoeken zonder treffers,
08 filmdetail, 09 seriedetail, 11 Mijn Pleya, 12 inloggen na een afgewezen poging, 13 lege
bibliotheek, 14 server onbereikbaar, 15 Home terwijl hij laadt, en de bibliotheeklijst (geen
eigen northstar-beeld). De staten 12 tot en met 15 zijn met `page.route` neergezet: een fout
wachtwoord, een lege itemlijst, een geweigerde `GET /info` en een vastgehouden hub-aanvraag.

Overloop: 85 metingen in het script, alle 0 px. Axe staat los hiervan in
`tests/e2e/a11y-routes.spec.ts` en in `scripts/gallery-axe.ts`.

## Testdata

Titels en artwork komen uit de e2e-testdata: de drie standaardtitels plus acht extra films
(kopieën van hetzelfde bestand) met gegenereerde verlopen als poster en achtergrond. Geen
TMDb-materiaal, dus geen echte posters; compositie en maat zijn te vergelijken, de inhoud niet.

## Bewuste afwijkingen van de northstar

- **Beheer-pil en avatar ontbreken in de kop.** De pil wijst naar `/admin`, en die route komt pas
  met S10. Voor de avatar draagt het contract geen beeld (`User` heeft alleen `username` en
  `role`). Open punt bij S7.2.
- **Boeken ontbreekt in de navigatie.** De testserver heeft geen boekenbibliotheek; het slot
  verschijnt alleen als die er is (capability-slot, `navItems.ts`).
- **Home heeft één rij.** Verder kijken, Volgende afleveringen en de rijen per bibliotheek zijn
  S8.1; de hero kiest het eerste item (M-6, ook S8.1). Zonder `playHref` staat er geen Afspelen,
  zonder `summary` geen synopsis.
- **12: het beeldvlak is het merkteken met de host.** Vóór het inloggen is er geen token, dus
  geen serverartwork, en `GET /info` draagt geen servernaam of aantallen.
- **13 zonder beheerknoppen.** Scannen en Serverbeheer zijn S10; de staat legt uit wat er is en
  wijst naar de bibliotheeklijst.
- **14 zonder tweede knop.** "Wat kan er aan de hand zijn?" heeft geen bestemming.
- **05 zonder filterrij.** Filters en facetten zijn S8 (PS-7F). De sortering is een `Select` en
  geen capsule.
- **08, 09 en 11 volgen hun beeld niet.** De indeling van detail (S8.5) en Mijn Pleya (S8.6) hoort
  bij S8; S7 heeft alleen de bestaande inhoud naar de primitieven gezet.
- **Atmosfeer op het bibliotheekraster.** De gekleurde achtergrond uit de artwork van de kaart
  onder de cursor kwam via `main` binnen (goedgekeurd ontwerp, `LibraryAtmosphere`) en staat niet
  in beeld 05.
