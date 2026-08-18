---
name: update-docs
description: Ververst de handleiding en de releasenotes op pleya.app en zet ze live. Gebruik bij "/update-docs", "documentatie bijwerken", "releasenotes bijwerken", of na een reeks commits die gebruikersgedrag veranderd hebben.
---

# /update-docs

Eén doorloop van bron naar live site. De volgorde ligt vast: releasenotes eerst, want
daaruit blijkt wat er veranderd is en dus welke hoofdstukken bij moeten.

Bronnen en bestemmingen:

| Wat | Waar |
|---|---|
| Releasenotes, publiek | `docs/RELEASES.md` |
| Handleiding, publiek | `website/src/lib/content/manual/*.md` (20 hoofdstukken) |
| Schotlijst voor beeld | `docs/manual/SCREENSHOTS.md` |
| Technisch logboek, intern | `docs/CHANGELOG.md`, `docs/DECISIONS.md`, `STATUS.md` |

Het interne logboek blijft intern. Kopieer er niets letterlijk uit: DEC-nummers, driftversies
en bestandspaden zeggen een gebruiker niets.

## 1. Preflight

```bash
git status --porcelain
```

Niet schoon? Stoppen en het melden. De rest van deze doorloop commit, en dan is niet meer te
zien wat van wie is.

## 2. Releasenotes

```bash
scripts/gen_release_notes.sh
```

Dat schrijft het blok tussen `<!-- BEGIN GENERATED -->` en `<!-- END GENERATED -->` onder
`## Unreleased` vol met commitregels sinds het `<!-- commit: … -->`-anker. Alles onder dat
blok is met de hand geschreven en wordt nooit aangeraakt.

Herschrijf die regels naar Engelse gebruikerstaal. De maatstaf is wat iemand merkt, niet wat
er in de code gebeurde: uit "drift v17: tabellen MediaInteractions + AffinitySnapshots" wordt
"Pleya now learns what you like, entirely on your device." Laat weg wat niemand ziet.

Is er sinds de vorige run een buildnummer opgehoogd?

```bash
git log --format='%h %ad %s' --date=short -20 -- pubspec.yaml | grep -i 'build number'
grep '^version:' pubspec.yaml
```

Zo ja: sluit `Unreleased` af tot een echte versiekop en zet het nieuwe anker erbij.

```markdown
## 2.8.0 · build 222 · 24 August 2026

<!-- commit: <sha van de bump-commit> -->
```

Laat `## Unreleased` daarboven staan met een leeg gegenereerd blok; de volgende run vult hem
weer. Draai `scripts/gen_release_notes.sh` daarna nog een keer: de tweede run hoort een lege
diff te geven.

## 3. Handleiding

Bepaal wat er sinds de vorige documentatiecommit is gebeurd:

```bash
LAST=$(git log -1 --format=%H --grep='^docs: handleiding en releasenotes bijgewerkt')
git diff --stat "$LAST"..HEAD -- lib/screens lib/widgets lib/i18n/en.i18n.json
git diff "$LAST"..HEAD -- lib/i18n/en.i18n.json | grep -E '^[+-] +"' | head -40
```

Geraakte schermen in `lib/screens/` en gewijzigde sleutels in `en.i18n.json` wijzen de
hoofdstukken aan. De koppeling loopt via de naam: `lib/screens/video_player/` hoort bij
`the-player.md` en `subtitles-and-audio.md`, `lib/screens/settings/` bij
`settings-reference.md`, enzovoort.

Werk het hoofdstuk bij en zet `updated:` in de frontmatter op vandaag. Alleen de hoofdstukken
die echt veranderd zijn: een datum die opschuift zonder tekstwijziging maakt "recently
updated" op `/docs` waardeloos.

Nieuwe schermafbeelding nodig? Zet hem in `docs/manual/SCREENSHOTS.md` en verwijs er in het
hoofdstuk naar. De pagina tekent vanzelf een plaatshouder tot het bestand er is.

## 4. Beeld

```bash
comm -23 \
  <(grep -oE '`[a-z0-9-]+\.png`' docs/manual/SCREENSHOTS.md | tr -d '`' | sort -u) \
  <(ls website/static/docs-media/ 2>/dev/null | sort)
```

Som op wat er nog mist. Niet blokkerend: de pagina's zijn zonder beeld af.

## 5. Proza

Alles wat je schrijft gaat eerst door de `anti-slop-text`-skill. Dat is een globale regel en
hij geldt hier onverkort. Let bij deze twee bestanden extra op:

- Geen em-dashes. De hook `~/.claude/hooks/anti-slop-check.sh` meldt ze met regelnummer en
  die melding is geen suggestie.
- Geen releasenote die alleen "verbeteringen en bugfixes" zegt. Dat is precies de tekst die
  dit hele traject moest vervangen.
- Elk punt noemt wat iemand merkt. Staat er geen waarneembaar gevolg in, dan hoort het in
  `docs/CHANGELOG.md` en niet hier.

## 6. Bouwen

```bash
cd website && bun run check && bun run build
```

`build/docs/` hoort twintig HTML-bestanden te bevatten en `build/releases.html` te bestaan.

## 7. Beeldcontrole

```bash
cd website && (bun run preview --port 4173 &)
for w in 390 1024 1440; do
  for p in docs docs/the-player releases; do
    pw screenshot --viewport-size=${w},2400 --wait-for-timeout=1500 \
      "http://localhost:4173/$p" "shot-$(echo $p | tr / -)-${w}.png"
  done
done
```

Kijken naar: geen horizontale scroll op het document, plaatshouders voor beeld op hun plek,
en de zijbalk die op 390 dichtklapt tot "All chapters". Toon de schermafbeeldingen als bewijs
in de terugkoppeling.

## 8. Live

```bash
website/deploy-nas.sh
curl -sI http://192.168.3.135:8830/docs | head -3        # 200, Cache-Control: no-cache
curl -s https://pleya.app/releases | head -5
```

## 9. Vastleggen

```bash
git add docs/RELEASES.md docs/manual website/src/lib/content/manual website/static/docs-media
git commit -m "docs: handleiding en releasenotes bijgewerkt"
```

Zet daarna de notities ook op de TestFlight-builds, zodat een tester ziet wat er nieuw is
zonder de site erbij te pakken:

```bash
fastlane notes build:<nummer>
```

Dat leest dezelfde sectie uit `docs/RELEASES.md` die je zojuist geschreven hebt en zet hem als
"What to Test" op alle drie de platforms. De lane is idempotent, dus opnieuw draaien na een
correctie kan gewoon.

De pre-push hook draait `gen_release_notes.sh` nog een keer. Schrijft hij iets, dan commit hij
dat en breekt de push af met de melding om opnieuw te pushen. Dat is bedoeld gedrag: git heeft
de te pushen refs al vastgesteld voordat de hook draaide.

Er wordt geen Dart aangeraakt, dus `dart run slang` en `flutter analyze` zijn hier niet nodig.
