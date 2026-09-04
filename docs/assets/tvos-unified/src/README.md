# Bron van de tvOS-mockups 09 tot en met 30

Dit is de werkmap waaruit de beelden in `../approved-2026-09-03/` en
`../mockups-2026-09-04/` geschoten zijn. Tot 4 september 2026 stond hij alleen in
`~/Downloads/mockups-tvos/_src`; hij staat hier zodat een volgende ronde een beeld
kan herschieten in plaats van het na te tekenen.

`tv.css` bevat de tokens. `build.mjs` zet de gedeelde topnav neer, kent de iconen
(`{{icon:naam}}`), lost `{{art:naam}}` op naar `../art/naam.jpg` en schiet elke pagina
op 1920x1080. `pages/*.html` zijn fragmenten, geen complete documenten. `assets/`
bevat Inter, Archivo Black, het wordmark en de avatar.

Twee dingen staan bewust niet in git. `art/` is TMDb-beeldmateriaal en hoort naast
deze map te staan; `out/` is wat `build.mjs` schrijft. De schermafbeeldingen landen in
`~/Downloads/mockups-tvos/` en worden met de hand naar de docs-map gekopieerd.

```
cd docs/assets/tvos-unified/src
node build.mjs                   # alles
node build.mjs 26-bibliotheken   # alleen mockup 26
```

Playwright komt uit de globale installatie onder `/opt/homebrew`; het pad staat in
`build.mjs`.
