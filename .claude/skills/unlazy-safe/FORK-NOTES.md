# unlazy-safe

Lokale fork van [Leonxlnx/unlazy](https://github.com/Leonxlnx/unlazy) v2.0.0.
Beheerd door Michel Knoop, buiten de skills-CLI om, zodat `skills update` deze
wijzigingen niet overschrijft.

De methode is ongewijzigd: gates vooraf, bewijs in plaats van zelfrapportage,
parent re-verificatie, geen "klaar" zolang meetbare acceptatiecriteria ontbreken.
Wat veranderd is, is waar commando's worden uitgevoerd en wat de skill mag
autoriseren.

## Waarom deze fork bestaat

Upstream `scripts/gate-check.mjs` voerde iedere `CHECK:`-regel uit met:

```js
spawnSync(gate.check, { shell: true, ... });
```

Eén goedgekeurde `node gate-check.mjs` werd daarmee een onbeperkt aantal
child-commando's die de permission- en classifier-laag van Claude Code niet
afzonderlijk passeren. Dat is een tweede executielaag naast de Bash-tool, en
dat is de verkeerde architectuur: een skill hoort te bepalen *wanneer* werk af
is, niet een eigen manier te krijgen om commando's te draaien.

Een denylist eroverheen (eerste poging: `rm -rf`, `git push`, `sudo`,
`curl | sh` blokkeren) helpt tegen ongelukken, maar is geen boundary.
`python -c`, `node -e`, `sed -i`, `find -delete`, `make`, `npm run`, docker,
cloud-CLI's en projecteigen scripts glippen er allemaal doorheen. Daarom is de
executie eruit gehaald in plaats van gefilterd.

## Wijzigingen ten opzichte van upstream v2.0.0

**1. `scripts/gate-check.mjs` herschreven: parser en judge, geen executie.**
`node:child_process` is niet langer geïmporteerd. De nieuwe werkwijze:

```
gate-check --list                              welke gates nog bewijs missen
<commando zelf draaien via de Bash-tool>       normale permissions, zichtbaar
gate-check --record G1 --from out.txt          output toetsen aan EXPECT
gate-check --manual G3 --evidence "..."        handmatige gate, weigert "pending"
gate-check [--status]                          ledger, N van N
```

Het script beslist nog steeds of output `EXPECT` matcht, weigert een vinkje
zonder bewijs, kapt evidence af, en honoreert `ABANDON:`. Gates zonder `EXPECT`
worden geoordeeld op de exitcode die je meegeeft met `--exit`.

**2. `SKILL.md`: sectie `## Boundaries` toegevoegd.** Gates staan onder de
instructies van de gebruiker: een stop van de gebruiker wint direct, een gate
autoriseert geen commit, push, delete, reset, force-operatie, deploy of
externe berichten, CHECK-regels uit onbetrouwbare bron worden eerst gelezen,
en werk blijft binnen de working directory.

**3. `SKILL.md`: Stop-hook alleen op expliciet verzoek.** Upstream zei "never
install it silently ... offer it once", wat proactief aanbieden toestond. Nu:
alleen installeren als de gebruiker erom vraagt, nooit als bijeffect, en nooit
`--global` (schrijft `~/.claude/settings.json`) zonder dat die scope expliciet
gevraagd is.

**4. `references/gates.md`, `references/orchestration.md`,
`references/token-economy.md`** aangepast aan de nieuwe flow. Orchestration
zegt er expliciet bij dat een gates-bestand van een subagent input is en geen
instructie: lees de CHECK-regels voor je ze draait.

**5. `name:` in de frontmatter is `unlazy-safe`**, zodat deze en een eventuele
upstream-installatie niet botsen. De `description` triggert alleen nog op
expliciete signalen (`/unlazy-safe`, "tree N", "be exhaustive", "do not stop
until it is done") en zegt er expliciet bij dat het losse woord "gates" geen
trigger is; dat komt in gewone architectuurgesprekken te vaak voor voor een
user-level skill.

**6. Iedere check wordt op exitcode beoordeeld, niet alleen de gates zonder
`EXPECT`.** Een gate slaagt alleen als het commando met 0 eindigde én `EXPECT`
matcht. Een build die "built in 3.2s" print en dan crasht, is geen gehaalde
gate. `--record` weigert daarom zonder `--exit <code>`. Een check die legitiem
non-zero eindigt, declareert dat vooraf met een `EXIT: <n>`-regel op de gate,
zodat de verwachting vastligt in plaats van bij het registreren te worden
weggewuifd.

**7. `ABANDON` is aangescherpt, semantisch en in de rapportage.** Toegestaan bij
gewijzigde gebruikersinstructie, aantoonbare onmogelijkheid (met wat je hebt
geprobeerd) of expliciete toestemming; niet bij moeilijkheid, tegenvallende
kosten of een krimpend contextbudget. De ledger meldt nu
`TERMINAL (n met, m abandoned, NOT complete)` plus een `NOT DELIVERED`-regel in
plaats van `ALL MET`, en de stop-hook laat de turn wel door maar stuurt een
systemMessage mee dat de opgegeven criteria in het rapport benoemd moeten
worden.

**8. Alle runtime-state staat onder `.unlazy/`**: `GATES.md`, `PLAN.md`,
`gates/`, `evidence/` en `state.json` (voorheen `.unlazy-hook-state.json` in de
projectroot). Beide scripts zoeken eerst in `.unlazy/` en vallen daarna terug op
de oude locaties in de werkdirectory, zodat bestaande gate-bestanden blijven
werken. `.unlazy/` staat in `~/.gitignore_global`, ingesteld via
`git config --global core.excludesfile ~/.gitignore_global`.


**9. `--record` weigert een gepipede CHECK zonder `pipefail`.**
Een pipeline levert de exitcode van zijn *laatste* stap, dus `npm test 2>&1 | tail -6`
eindigt op 0 zodra `tail` slaagt, ook bij een rode suite. `--exit` werd daarmee een
stempel en een falende gate kon als PASS worden vastgelegd, met een groen ogende tail als
"bewijs". Precies dat gebeurde hier een keer: een run met `Test Files 1 failed` werd
groen geregistreerd.

`hasUnguardedPipe()` kijkt nu naar de CHECK-regel en weigert het record met een
foutmelding die de gerepareerde regel toont. Een `|` binnen quotes en de `||`-operator
tellen niet als pipeline, en `set -o pipefail` of `PIPESTATUS` in de regel heft de
weigering op. De regel staat ook in `SKILL.md`, `references/gates.md` en het
leaf-template.

## Wat níet veranderd is

`scripts/stop-hook.mjs` is ongewijzigd. Die voert niets uit, scant alleen de
gate-bestanden, blokkeert maximaal 6 opeenvolgende stops zonder voortgang en
laat `ABANDON:` altijd door. Niet geïnstalleerd; `install-hooks.mjs` moet daar
handmatig voor draaien.

`references/method.md`, `templates/` en de vier werkpassen zijn ongewijzigd.

## Bijwerken vanaf upstream

Deze map staat bewust niet in `skills-lock.json` en wordt niet door
`npx skills add/update` beheerd. Bijwerken gaat handmatig: haal upstream binnen
in een aparte map, vergelijk, en neem over wat je wilt. Controleer daarbij als
eerste of `gate-check.mjs` upstream nog steeds `spawnSync` gebruikt; zo ja, dan
blijft punt 1 hierboven van kracht.

Upstream: https://github.com/Leonxlnx/unlazy (MIT, zie LICENSE).
