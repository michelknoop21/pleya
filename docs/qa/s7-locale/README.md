# Opnamen S7.5 taak 5: afbreken op taal en langer Nederlands

Alles in het donkere thema. Elke opname staat er twee keer, een keer met de browser op
`en-US` en een keer op `nl-NL`, met `pleya.locale` gewist zodat de browsertaal beslist.

## Galerij (`galerij-en/`, `galerij-nl/`)

Gemaakt tegen `vite dev` met:

```bash
PLEYA_DEV_URL=http://localhost:5199 PLEYA_SHOTS_THEME=dark \
  PLEYA_SHOTS_SECTIONS=kaarten,hero,rail,tabel,knoppen \
  bun run scripts/primitives-shots.ts ../docs/qa/s7-locale/galerij-nl --locale nl
```

| Opname | Breedtes | Wat hij laat zien |
| --- | --- | --- |
| `hero@*.png` | 393, 1024, 1600 | Hero B draagt "Kinderboekenweekgeschenk Arbeidsongeschiktheidsverzekering Zandkasteelwedstrijdkampioenschappen". In `nl` breekt elke samenstelling op een lettergreep met streepje (Kinderboe-kenweekge-schenk op 393). In `en` breken dezelfde woorden midden in een lettergreep zonder streepje: dat is de negatieve controle. Vanaf 900 houdt de titel vier regels aan, met een beletselteken op 1024 en 1600. |
| `rail@*.png` | 393, 1024, 1600 | De derde rij heet "Recent toegevoegd: Kinderboekenweekgeschenken". Op 393 loopt de titel over twee regels met een streepje en blijft "Alles bekijken" rechts naast de titel staan in plaats van eronder te vallen. |
| `kaarten@*.png` | 393, 1024, 1600 | De resterende tijd per taal ("nog 1u 12m" tegen "1h 12m left"). Het paneel van de kaart zonder artwork draagt nu `hyphenate`; "The Zone of Interest" past op spaties en laat dat hier nog niet zien. |
| `tabel@*.png` | 393, 1024, 1600 | De galerijtabel heeft vaste Nederlandse labels en ziet er in beide talen gelijk uit. `DataTable` komt nog op geen echte route voor; de tabelkoppen zijn dus alleen hier te toetsen, en de `<dl>` op `/server` staat bij de routes. |
| `knoppen@*.png` | 393, 1024, 1600 | De langste knoplabels uit de catalogus. Geen knop breekt of wordt lager dan 44 px; gemeten op 393 in `nl`: "Eigenaar aanmaken" naast "Annuleren" op 177 px elk, `scrollWidth` gelijk aan `clientWidth`. |

## Echte routes (`routes/`)

Tegen de e2e-stack (`scripts/e2e-stack.sh up`), per taal op een verse stack, omdat `/setup` alleen
bestaat zolang de server geen eigenaar heeft:

```bash
bun run scripts/screenshots.ts ../docs/qa/s7-locale/routes --locale nl
```

Bestandsnaam `dark-<breedte>-<scherm>-<taal>.png`, voor `home`, `library-grid`, `server`, `setup`
en `login` op 393, 1024 en 1600. TopNav vanaf 900, MobileHeader en TabBar eronder.

Wat ze bewijzen:

- de TabBar op 393 toont "Mijn Pleya" zonder afkappen;
- de capaciteitenlijst op `/server` overlapte op 1024 in `nl` ("niet beschikbaar" schoof over
  `watch_state_ownership`); de rij laat de status nu naar een eigen regel zakken;
- `/setup` en `/login` passen in beide talen, "Eigenaar aanmaken" over de volle breedte.

Het script meet daarnaast op 393, 768, 1024, 1280 en 1600 de horizontale paginaoverloop. Alle
vijftig metingen (vijf schermen, vijf breedtes, twee talen) gaven 0 px.

## Bewuste beperkingen

- Een mediatitel krijgt de taal van de interface. Het protocol heeft geen taalveld per titel, dus
  een Engelse filmtitel wordt in een Nederlandse interface met Nederlandse regels afgebroken.
- `hyphenate-limit-chars` staat er niet in: Safari ondersteunt het niet (MDN browser-compat-data).
- De bijschrifttitel onder een kaart blijft één regel met een beletselteken; afbreken werkt daar
  alleen op het paneel van een kaart zonder artwork.
- De e2e-stack levert geen posters, dus de kaarten op de routes zijn panelen zonder beeld.
