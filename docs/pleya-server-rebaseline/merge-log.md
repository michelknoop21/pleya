# Merge-log: `feat/pleyaserver` naar `main`

Dit bestand is de meting en het stappenplan voor slice S0. Het legt vast wat een proefmerge
werkelijk oplevert, welke conflicten er zijn, en in welke volgorde ze worden opgelost. Het is
geen verslag achteraf: taak S0.3 wordt afgevinkt tegen de lijst hieronder.

## 1. Meting van 4 september 2026, avond

Gemeten in een wegwerp-worktree op `main`, nooit in de werkcheckout (`git worktree add --detach`
in de scratchpad, daarna opgeruimd).

| Meting | Uitkomst |
| --- | --- |
| `git rev-list --left-right --count main...HEAD` | 196 aan de kant van `main`, 49 aan de kant van `feat/pleyaserver` |
| `main` bij het begin van de meting | `0ad49ec` |
| `main` twintig seconden later | `64b0105` |
| `origin/main` | `80934b9` (lokale `main` loopt vooruit op de remote) |
| Proefmerge | `git merge --no-commit --no-ff feat/pleyaserver` faalt met 14 conflictbestanden |
| Bestanden die schoon auto-mergen | 26 |

De twee `main`-sha's staan er met opzet in. Er werkt op dit moment een andere sessie op `main`, en
tijdens deze meting verschoof hij. Het pakket noemde nog `2433f74`; dat is inmiddels 196 commits
oud. Vraag 58 zegt daarom "vanaf de dan gestabiliseerde actuele `main`": de integratiebranch wordt
pas afgetakt als er niemand meer op `main` schrijft, en de meting hieronder wordt op dat moment
herhaald. De conflictlijst is de vorm die je mag verwachten, niet een garantie op precies deze
regels.

## 2. De conflicten, per bestand

| Bestand | Hunks | Wat het is | Oplossing |
| --- | --- | --- | --- |
| `docs/DECISIONS.md` | 1 | de twee lijsten schuiven in elkaar; git ziet geen probleem | zie hoofdstuk 3, de nummering is het echte werk |
| `docs/CHANGELOG.md` | 1 | twee logboekregels op dezelfde plek | beide houden, chronologisch |
| `docs/RELEASES.md` | 1 | gegenereerd blok tegen gegenereerd blok | `scripts/gen_release_notes.sh` opnieuw draaien na de merge, nooit met de hand |
| `STATUS.md` | 3 | sessielogboek van beide kanten | beide houden, chronologisch |
| `docs/sessions/2026-08-24.md` | 2 | idem | beide houden |
| `docs/sessions/2026-09-03.md` | 1 | idem, en er ligt ongecommit werk van een andere sessie | beide houden; de wijziging van die sessie eerst laten landen |
| `docs/sessions/2026-09-04.md` | 1 | idem | beide houden |
| `CLAUDE.md` | 1 | `main` heeft de brand-assets-bullet uitgebreid met DEC-079, de branch heeft de korte versie | `main` wint |
| `pubspec.yaml` | 1 | buildnummer 250 tegen 242 | het hoogste wint (`main`) |
| `tvos/scripts/xcode_appletv.sh` | 1 | `main` voegde `PLEYA_VERIFY` toe, de branch `PLEYA_GIT_COMMIT`, op dezelfde regel | beide vlaggen houden |
| `lib/i18n/nl.i18n.json` | 2 | beide kanten voegden sleutels toe in hetzelfde blok | beide houden, daarna `dart run slang` |
| `lib/i18n/strings.g.dart` | 1 | gegenereerd | niet met de hand oplossen: `dart run slang` |
| `lib/i18n/strings_en.g.dart` | 3 | gegenereerd | idem |
| `lib/i18n/strings_nl.g.dart` | 6 | gegenereerd | idem |

Geen enkel conflict zit in productiecode. De inhoudelijke conflicten zijn een buildnummer, een
regel in `CLAUDE.md`, een regel in een tvOS-script en twee i18n-blokken; de rest is logboek of
gegenereerd.

## 3. De vijf voorspelde conflicten die er geen zijn, en waarom dat erger is

Het re-baseline-pakket noemde vijf bestanden als bekende conflicten. Ze conflicteren geen van
alle. Ze verschillen wel op beide takken:

| Bestand | `main` | `feat/pleyaserver` | Uitkomst van de merge |
| --- | --- | --- | --- |
| `lib/media/server_capabilities.dart` | `74d1715f` | `922d1fda` | schoon samengevoegd |
| `lib/models/pleya_server/pleya_wire.dart` | `fa8895b7` | `e3a09bca` | schoon samengevoegd |
| `lib/profiles/profile.dart` | `4b7886e3` | `b450dbab` | schoon samengevoegd |
| `lib/database/app_database.dart` | `5730f4b7` | `d6255da1` | schoon samengevoegd |
| `lib/services/offline_watch_sync_service.dart` | `50ced412` | `96798923` | schoon samengevoegd |

Een schone tekstuele merge is hier geen bewijs. `userRating` staat na de merge één keer in
`server_capabilities.dart` en `sessions` één keer in `pleya_wire.dart`, en geen enkele klasse
heeft een dubbel veld, maar dat toont alleen aan dat er geen letterlijke duplicatie is. Wat het
niet toont: of de gegenereerde `.freezed.dart` en `.g.dart` nog bij de samengevoegde bron passen,
en of de writepropagatie en de reference managers uit `app_database.g.dart` de merge hebben
overleefd. Het risico is daarmee verschoven van een conflict dat je ziet naar een regressie die
je alleen met bewijs vindt. S0.3 is pas klaar bij:

1. `scripts/codegen.sh` met een **lege** gegenereerde diff (draaien op de SDK uit `.fvmrc`);
2. `flutter test`, met `test/database/drift_relations_test.dart` expliciet groen, want die test
   bewaakt precies wat hier stil kan sneuvelen;
3. `scripts/ci_checks.sh`.

## 4. De DEC-nummering

`docs/DECISIONS.md` mergt zonder conflictmarkering en houdt daarna **twaalf dubbele nummers**
over: DEC-063 tot en met DEC-073 (elf) plus DEC-093. Het bestand telt na de merge 105 koppen. Git
meldt hier niets over; alleen een grep vindt het.

| Nummer | Op `main` | Op `feat/pleyaserver` |
| --- | --- | --- |
| 063 | Pleya Unified TV 2026, architectuurbaseline | refreshtokenrotatie met respijtvenster |
| 064 | Films en Series als twee niveaus | het hardwarecriterium van PS-5 blokkeert PS-9 niet |
| 065 | visuele north star TV 2026 bevroren | rollen- en rechtenmodel voor PS-9 |
| 066 | search unified projectie TV-only | intrekkingsregister met een grens |
| 067 | de TV-hero dedupliceert in fase 6 | PS-9 levert een gebruikersbeheer-API |
| 068 | de complete-catalogusactie naast de paginatitel | het protocolvenster gaat open voor PS-9 |
| 069 | de TV-root heeft één geneste routestapel | `sid` loopt door de volledige authketen |
| 070 | de Home-carousel roteert na inactiviteit | sessie-inzage en -intrekking als eigen API |
| 071 | bekeken is bekeken over alle bronnen | bestaande refreshketens krijgen een `legacy`-sessie |
| 072 | spatial D-pad volgt de geometrie | de endpoint- en autorisatiematrix is bindend |
| 073 | de TV-shellkeuze is niet schakelbaar | PS-4E, PS-7N en PS-7A erbij, PS-4W geknipt |
| 093 | de catalogusacties op TV in een rail | e-books worden een contentdomein |

De twaalf van `feat/pleyaserver` worden hernummerd, niet die van `main`: `main` is de boom waar de
rest naartoe merget. Het pakket noemde 096 als startpunt. Dat is **geen toezegging** (vraag 59).
De stand op dit moment: `main` gaat tot 094, `feat/netflix-mobile` claimt 095 en `feat/ebooks`
claimt 094. Welk nummer vrij is hangt dus af van wat er vóór deze merge landt. De regel is:
inventariseer bij de integratie het hoogste geldige nummer in de samengestelde boom en hernummer
naar de eerstvolgende vrije reeks van twaalf, aaneengesloten.

Bij het hernummeren horen in dezelfde commit: de koppen, de ankers (`#dec-0nn-...`), elke
verwijzing in `docs/`, `CLAUDE.md`, `STATUS.md` en de codecommentaren, plus een mappingtabel oud
naar nieuw onderaan `docs/DECISIONS.md`. Bewijs is een grep op de oude nummers die alleen de
mappingtabel nog raakt.

## 5. Volgorde van uitvoering in S0

1. Wachten tot `main` stilligt; de meting uit hoofdstuk 1 herhalen en de sha noteren.
2. `integration/pleya-server-rebaseline` aftakken van die `main` (vraag 58).
3. `feat/pleyaserver` erin mergen met een merge-commit.
4. De veertien conflicten oplossen in de volgorde van hoofdstuk 2: eerst de gegenereerde
   bestanden **niet** met de hand maar via `dart run slang` en `scripts/codegen.sh`, dan de
   handmatige, dan de logboeken.
5. De DEC-hernummering als **eigen commit**, zodat de mappingtabel los te lezen is.
6. Het bewijs uit hoofdstuk 3 draaien, plus `pleya_server/scripts/verify-local.sh` en de
   webcontroles (check, test, build, e2e).
7. Pas daarna de CI-jobs toevoegen en één groene run halen (S0.5).

Stap 4 en 5 gaan niet in één commit. Een hernummering die tussen de conflictoplossingen zit is
niet meer te reviewen, en dat is precies het soort commit waar een verkeerd ankertje maanden
onopgemerkt blijft.
