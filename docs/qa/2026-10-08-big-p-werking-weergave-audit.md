Method: dual-agent (A: /root/bigp_functional_audit · B: /root/bigp_visual_audit)

# Big P: audit werking en weergave op tvOS — 8 oktober 2026

Roadmap: BP-00/BP-04b/BP-05/BP-06/BP-09. Bronstand `bdedec38b59ce31549d7b522164ca8fc1c149654`. Registratie AUDIT-BIGP-UX1. **Read-only productaudit: geen appwijziging, nieuwe ontwerpapproval, release of volledige hardware-/modelacceptatie.** Bestaande tvOS-klantbelevingsaudit blijft afzonderlijk; dit is een verdieping van het Big P-domein onder de actuele roadmap. Het besluit van8oktober heft de eerdere exclusieve stroom op; deze audit verandert zelf geen uitvoeringsprioriteit of WIP.

## Oordeel

Big P heeft een bruikbare, samenhangende presentatie en substantiële beschermingen voor uitvoeren en annuleren. De belangrijkste vraag is of de kijker even zeker weet wat gebeurd is als de code. De onderzochte weigering werkt correct aan de uitvoerkant, maar de enkele-taakpresentatie kan modeltekst laten voorgaan op de werkelijke annuleringsstatus. Daar ligt meer productwinst dan in een nieuwe visuele shell.

Geen Critical vastgesteld in deze begrensde review. Dat is geen volledige securitygoedkeuring. Er zijn geen live providerantwoorden, echte gebruikersdata of native Big P-journeys uitgevoerd. De werkingstest is gemockt; de nieuwe beelden zijn widgetrenders.

## Concrete bevindingen

**F1 — Important/P1, bronbevestigde route, native effect kandidaat; BP-05.** Een geweigerde enkele actie kan modeltekst “ok” tonen zonder eigen annuleringsstatus. `big_p_labels.dart:164-170` kiest eerst modeltekst; `tv_assistant_conversation.dart:356-365` tekent alleen een resultaatkaart bij error of uitgevoerde acties. De controller behandelt een cancelled task niet als resultIsError (`assistant_controller.dart:472`). Test `assistant_controller_test.dart:416-430` geeft na weigeren `_say('ok')`, nul uitvoering en cancelled task. Dit bewijst het codepad, geen echte modelincidentie of screenshot van die toestand. Multitaak heeft wel eigen cancelled-status. Verbetering: een code-eigen neutrale uitkomst “Geannuleerd · niets uitgevoerd” boven modelproza; behouden dat weigeren niets uitvoert. Geen ongeautoriseerde uitvoering aangetoond, geen bewezen nieuwe regressie.

**F2 — Minor/P2, bronbevestigde herstelroute, native fout niet gereproduceerd.** Bij een exception in native tekstinvoer wordt gelogd en geannuleerd; de oproepvorm kan sluiten (`tv_assistant_screen.dart:233-239`, `tv_assistant_summon.dart:189-200`). Voor de kijker lijkt dit op bewust afbreken. Voeg herkenbare invoerfout met opnieuw-proberen toe zonder Menu/Back als fout te behandelen.

**F3 — Important/P1, native kandidaat; BP-09.** Het volledige Big P-scherm houdt paneel/mascotte op een vaste bodempositie bij luisteren (`tv_assistant_screen.dart:330-390`), terwijl de oproeplaag de bottom expliciet naar430pt verhoogt (`tv_assistant_summon_layer.dart:37-38`). Motionbeeld38-2 toont vrijhouding boven het systeemtoetsenbord. Alleen als het native toetsenbord Flutter niet voldoende herschaalt kan overlap optreden. Eerst een echte fullpage-Ask-capture maken; geen fix of acceptatie uit een synthetisch toetsenbord afleiden.

**F4 — Minor/P2, bronbevestigd beperkt verschil.** Twee lezers gebruiken altijd240ms `animateTo`, ook bij Reduce Motion (`big_p_answer.dart:175,342`); andere Big P-animaties houden met die voorkeur rekening. Consistent maken met bestaand beleid is een kleine toegankelijkheidsverbetering. De motion-authoriteit verbiedt niet iedere door de gebruiker gestarte scroll: geen grote contractschending claimen.

**F5 — Minor/P3, ontwerpdelta ter afweging.** Motionautoriteit38:248-249 noemt wijzen naar de gefocuste titel. De owners geven een point-target alleen tijdens werken (`tv_assistant_screen.dart:351`, `tv_assistant_summon.dart:385-387`), niet op resultaatfocus. De kaarten hebben al duidelijke focusringen. Eerst bepalen of dit gedrag na ballon39J nog wenselijk is; geen extra focusframework bouwen om een ouder detail af te vinken.

**F6 — Minor, autoriteitsambiguïteit.** Gate schakelt tickers expliciet uit (`tv_assistant_gate.dart:45-48`), terwijl motionronde2 spreekt over altijd levend behalve Reduce Motion. Mogelijk is de rustige gate een bewuste uitzondering. Reconcile eerst de tekst; geen bewezen klantbug en geen opdracht om gateanimatie toe te voegen.

## Sterktes

- Bevestiging heeft een eigen Pleya-kaart met veilige beginfocus; FIFO, identiteit en verlopen kaarten zijn gemockt getest. Modeltekst beslist geen bevoegdheid.
- Meerdere opdrachten behouden afzonderlijke status en eerdere acties na een latere fout. Stoppen, nieuw gesprek en budgetgrenzen hebben gerichte dekking.
- Kaarten, lange-tekstscroll, vervolgvragen en compacte oproepresultaten bestaan al. Oude fixed meldingen over markdown, automatische sluiting, lege grids of mondtiming worden niet opnieuw als ontbrekende functies gemeld.

## Ontwerp en vensters

De 38-set is de goedgekeurde baseline, aangevuld door het motionprototype en latere BIGP-HW-/BIGP-39J-registerbesluiten. Oude zinnen over geen overlay of geen beweging in het38-manifest zijn geen reden om de huidige ballon terug te draaien. Specificiteit: Pleya's eigen avatar, glassurface, witte acties en brongebonden kaarten zijn onderscheidend; er is geen reden voor een generieke chatbotlayout.

[Approval38](../tvos-redesign-38-big-p-approved.md), [gedragscontract](../big-p-behaviour-contract.md), [fysieke register](../tvos-fysieke-correctieronde.md). Een gekoppeld hoofdbeeld dekt niet automatisch elk subformulier of foutgeval. Niet gekoppelde substanden hieronder zijn beoordelingsvoorstellen, geen bewezen ontwerpafwijkingen.

| ID | Venster / toestand | Referentie | Behouden / verbeteren / controleren | Eigenaar |
| --- | --- | --- | --- | --- |
| BP-AUD-01 | Ingang Mijn Pleya | 38A / fysieke register | Behoud één herkenbare ingang; oproepen is aanvullend volgens latere registerbesluiten. | `lib/screens/tv/assistant/tv_assistant_gate.dart` |
| BP-AUD-02 | Oproepen Play/Pause | BIGP-PP1 / BIGP-39J | 600ms-hold bestaat; korte druk, native editor en actieve speler op hardware toetsen. | `lib/screens/tv/assistant/tv_assistant_summon_layer.dart` |
| BP-AUD-03 | Geen toegang / kinderprofiel | 38B + gedragscontract | Rechten en uitleg scheiden van ontbrekende configuratie; geen model mag rechten geven. | `lib/screens/tv/assistant/tv_assistant_gate.dart` |
| BP-AUD-04 | Niet ingesteld | 38C1/C2 | Eén concrete uitweg naar instellen; keychainfout is iets anders dan nooit ingesteld. | `lib/screens/settings/assistant_settings_screen.dart` |
| BP-AUD-05 | Provider / model kiezen | 38C2 | Huidige keuze, bereikbaarheid, model en opslaan begrijpelijk houden; geen automatische providerwissel. | `lib/screens/settings/assistant_settings_screen_models.dart` |
| BP-AUD-06 | Testen / opslaan / wijzigen | 38C2 / BIGP-KC1 | Bestaande testgate en opgeslagen sleutel behouden; cross-device keychain nog hardware-open. | `lib/screens/settings/assistant_settings_screen_views.dart` |
| BP-AUD-07 | Rust / begroeting | 38D + motionprototype / register | Voorbeelden helpen beginnen; groen bronlabel niet lezen als bewijs van actuele modelbereikbaarheid. | `lib/screens/tv/assistant/tv_assistant_conversation.dart` |
| BP-AUD-08 | Luisteren / dicteren | 38E + native-inputcontract | Echte UIKit/spraak op toestel toetsen; gemockte invoer bewijst Send/Back-flow, niet herkenning. | `lib/screens/tv/assistant/tv_assistant_screen.dart` |
| BP-AUD-09 | Tekstinvoer mislukt | 38E; geen aparte foutmockup gekoppeld | Code logt uitzondering en annuleert/sluit; expliciete melding en retry verbeteren herstel. | `lib/screens/tv/assistant/tv_assistant_summon.dart` |
| BP-AUD-10 | Bezig / stappen | 38F / BP-09 | Bestaande staplabels, stopknop en nog-controlerenstatus behouden; niet klaar suggereren bij eerste kaart. | `lib/screens/tv/assistant/tv_assistant_conversation.dart` |
| BP-AUD-11 | Meerdere opdrachten | BP-09 / gedeeld gedragscontract | Per taak resultaat en status; één mislukking wist eerder uitgevoerde acties niet. | `lib/screens/tv/assistant/tv_assistant_tasks.dart` |
| BP-AUD-12 | Stoppen / annuleren | Gedragscontract / BP-05 | Uitvoering is beschermd; één geweigerde taak mist mogelijk deterministische zichtbare annuleringsstatus. | `lib/widgets/big_p/assistant/big_p_labels.dart` |
| BP-AUD-13 | Bevestigen / weigeren | 38H/I + gedragscontract | Pleya-kaart, onderwerp, gevolgen en veilige beginfocus behouden; FIFO en stale-confirmbescherming getest. | `lib/screens/tv/assistant/tv_assistant_confirm_flow.dart` |
| BP-AUD-14 | Wachtwoordbevestiging | 38H/I; subeditor niet apart gekoppeld | Geen wachtwoord in modelgesprek; native invoer en herstel fysiek controleren. | `lib/widgets/big_p/assistant/big_p_confirm_card.dart` |
| BP-AUD-15 | Resultaat: titelkaarten | 38G + BIGP-HW12–15 | Kaarten zijn concrete acties; eerste kaart bereikbaar, lijst boven lange tekst; bestaande densityfixes behouden. | `lib/widgets/big_p/assistant/big_p_match_card.dart` |
| BP-AUD-16 | Resultaat: kijkcijfers | 38G + BIGP-HW12 | Gebruiker, periode en brondekking belangrijker dan een mooie volledige ranglijst suggereren. | `lib/widgets/big_p/assistant/big_p_watch_card.dart` |
| BP-AUD-17 | Resultaat: tekst zonder kaarten | 38G + BIGP-HW14/15 | Lange tekst scrollbaar vanaf begin; platte tekst en scherpe laatste regel behouden. | `lib/widgets/big_p/assistant/big_p_answer.dart` |
| BP-AUD-18 | Vroege deelresultaten | BP-09 / BP-05 | Nog controleren zichtbaar houden; kaarten en eindantwoord uit dezelfde bewezen set laten volgen. | `lib/screens/tv/assistant/tv_assistant_conversation.dart` |
| BP-AUD-19 | Vervolgvragen | BIGP-HW12 / BP-06 | Drie huidige suggesties behouden; echte contextkwaliteit testen met korte verwijzingen zoals die tweede. | `lib/widgets/big_p/assistant/big_p_suggestions.dart` |
| BP-AUD-20 | Nieuw gesprek | BP-06/08; bestaande resetcontracten | Gesprek/taak staat resetten, blijvende voorkeuren apart; geen oude scope meenemen. | `lib/screens/tv/assistant/tv_assistant_screen.dart` |
| BP-AUD-21 | Providerfout / model verdwenen | Gedragscontract; geen aparte foutmockup gekoppeld | Gerichte fouttekst en model-insteluitweg bestaan; netwerkfalen in echte app nog niet getest. | `lib/widgets/big_p/assistant/big_p_labels.dart` |
| BP-AUD-22 | Taakstatus onbekend / achtergrond | BP-01 / gedragscontract | Onbekend blijft onbekend; geen succes alleen omdat HTTP-aanroep terugkwam. | `lib/widgets/big_p/assistant/big_p_results.dart` |
| BP-AUD-23 | Leeftijd / kindervraag | Gedragscontract; aanvullende kaart | Bestaande leeftijdskeuze en toegangshandhaving behouden; onbekend niet invullen met gok. | `lib/screens/tv/assistant/tv_assistant_kids_sheet.dart` |
| BP-AUD-24 | Hoofdscherm / glaspaneel | 38 + BIGP-HW15 | Nieuwe widgetbeelden beoordelen geometrie; echt glas, TVafstand en native keyboard vragen toestel. | `lib/screens/tv/assistant/tv_assistant_screen.dart` |
| BP-AUD-25 | Oproepballon / terugkeer | BIGP-39J boven oudere38-overlaytekst | Ballon is huidige oproepvorm, fullpage behoudt glas; Menu en focusring hardware-open. | `lib/screens/tv/assistant/tv_assistant_summon.dart` |
| BP-AUD-26 | Avatar / mond / geluid | Motionprototype + BIGP-HW8/9 | Clipgestuurde mond en suppressie tijdens playback getest; klank/volume/ReduceMotion fysiek toetsen. | `lib/widgets/big_p/assistant/big_p_voice_mouth.dart` |
| BP-AUD-27 | Intent / persoonskeuze | BP-04b / gedragscontract | Keywordparser bestaat; wedervraag/classifier-gaten zijn gepland werk, geen voltooid gedrag. | `lib/assistant/assistant_intent.dart` |
| BP-AUD-28 | Gespreksgeheugen / bronnen | BP-06/08 / gedragscontract | Modelgesprek niet gelijkstellen aan expliciet, gestructureerd intentgeheugen; echte brondekking toetsen. | `lib/assistant/assistant_controller.dart` |

## Gebruikstoets

Geen numerieke styling-/gezondheidsscore: native beeld, toegankelijkheid en semantische modelkwaliteit zijn onvoldoende gedekt. Bron- en widgetbeoordeling per principe:

| Principe | Oordeel | Bewijs / resterende vraag |
| --- | --- | --- |
| Systeemstatus | Bruikbaar, inconsistent bij enkele annulering | Taakstatus/stappen bestaan; F1 vraagt eigen uitkomst. |
| Kijkerswereld | Herkenbaar | Titelkaarten en Vraag/Nieuw/Klaar; technische configuratie blijft een drempel. |
| Controle/vrijheid | Sterke gemockte dekking | Stoppen, weigeren, Menu en nieuw gesprek; native route nog open. |
| Consistentie | Kleine delta's | Enkele/multitaakuitkomst en Reduce Motion. |
| Foutpreventie | Gerichte checks positief | Bevestiging en rechten; geen volledige securityaudit. |
| Herkennen | Sterk in fixtures | Kaarten, status en vaste knoppen; brononzekerheid in echte antwoorden toetsen. |
| Efficiëntie | Bestaande focus/compacte lijst bruikbaar | 6 focus/ruimtechecks; echte remotejourney ontbreekt. |
| Esthetiek/minimalisme | Componentsamenhang zichtbaar | 22 renders; productieachtergrond en TVafstand niet gecertificeerd. |
| Foutherstel | Gerichte verbetering nodig | F2, provideruitwegen bestaan. |
| Hulp | Voorbeelden aanwezig | Werkelijke vervolgcontext en onbekende personen nog modelpoort. |

## Klantbeleving en cognitieve belasting

Dagelijkse kijker: snel van vraag naar kiesbare titel, met begrijpelijke wachttijd. Nieuwe gebruiker: providerconfiguratie en toegang zijn verschillende problemen. Beheerder: bevestiging en feitelijke uitkomst zijn belangrijker dan een overtuigend modelantwoord. Kind-/familievragen: expliciete scope en leeftijden mogen niet worden gegokt. Visuele/motorische toegankelijkheid: focus, actieve staat, lange tekst en gebaren op echte afstand en hardware testen.

Veel titelkaarten zijn geen probleem op zichzelf. De beslislast zit in de vraag of een antwoord compleet is, een kaart al definitief is en een wijziging werkelijk is uitgevoerd. De gewenste piek is een passend resultaat kunnen openen; de vallei is annuleren en daarna toch een bevestigend antwoord lezen. Houd technische providerkeuzes bij instellen en begrijpelijke uitkomsten in het gesprek.

## Bewijs en beperking

- A: 189 tests passed, 2 skipped; `/tmp/pleya-bigp-functional-tests.log`. Controller, voice, conversation memory, tvOS screen/tasks/new conversation en settings; geen volledige suite.
- Root: 67 passed, 2 skipped; `/tmp/pleya-bigp-settings-tests.log`. Provider-keychain + settings. Deze settingsdekking overlapt met A: **niet optellen tot een unieke testtelling.** De twee settingsskips vragen `kPleyaVerify`, regels505/515; gewone tests bewijzen die instrumentationfocus niet.
- B: 22/22 verse renders en6/6 gerichte balloon/space/followupchecks, logs `/tmp/pleya-bigp-shots.log`, `/tmp/pleya-bigp-visual-tests.log`. Screenshotmanifest `.build/audits/big-p-2026-10-08/manifest.json` bevat staat, 1920×1080, SHA256 en bestandspad. Root heeft aanvullend summon-result-matches en surface-confirm visueel bekeken; B alle22.
- Alle22: Nederlandse tekst, donker thema, Reduce Motion aan, AppleTV-schaal1.85, gemockte controller/native keyboard, fallbackposters. **Historische statische Home-reference als achtergrond**, niet de actuele productieroute. Gates lijken daardoor boven ongedimde Home te staan: een harnessartefact, geen productiecontrastbug. Providersettings/multitaak/licht/OLED/native toetsenbord zijn geen screenshotdekking van deze set.
- Beelden: summon-idle/listening/working/working-streamed; summon-result-short/long/matches/watch/grid/options/action/error; summon-confirm/kids-ages; surface-idle/result-long/result-matches/result-watch/confirm/kids-ages/gate-setup/gate-locked, alle `.png` in evidence-map.
- B werkelijk bekeken: goedgekeurde39J `docs/assets/ios-unified/big-p-39/39-j-tvos-variant.png`, motion38-2 `docs/assets/tvos-unified/mockups-2026-10-02-big-p/motion/38-motion-2.png`. Dit zijn doelbeelden, geen runtimebewijs.
- Detector op `lib/screens/tv/assistant`: exit0, `[]`; Dart unsupported / nul scannable frontendfiles. **Geen clean-auditclaim** uit dat resultaat. A was afgerond voordat B-uitvoer in de synthese werd gelezen.
- Geen code-/lockfilewijziging. Geen Flutter CI-gate voor docs-only audit. `git diff --check` en documentlinks worden gecontroleerd; onafhankelijke documentreview vond verouderde stroomframing; die is aangepast aan het actuele8oktoberbesluit.
- Actuele native inputblokker uit voorafgaande audit: idb mist SimulatorKit bij eerste HID-actie. De eerdere Home-opname is geen Big P-runtimebewijs. Geen herhaalde native run zonder gewijzigde toolchain.
- Geen echt provider/model, Plex/Jellyfin/Emby/PleyaServer/Tautulli/Seerr, gedeelde iCloud-keychain, Siri Remote, dictatie, audio-volume of ReduceMotion live gevalideerd. Gemockte uitvoer bewijst geen semantische modelkwaliteit of echte gegevensdekking.

## Acceptatie die nog ontbreekt

1. Enkele schrijfactie weigeren, accepteren en bevestiging laten verlopen: uitkomsttekst én nul/één werkelijke mutatie vergelijken.
2. Drie opdrachten, één mislukt en één geannuleerd: telling, kaarten en antwoord moeten hetzelfde zeggen.
3. “Ik”, “anderen”, gemengde doelgroep, vorige week en onbekende persoon: geen stil verbreden; bekende BP-04b-gaten apart loggen.
4. “Die tweede”, andere soort en periode in vervolg: gesprekscontext en actuele expliciete keuze toetsen; BP-06 niet als voltooid claimen.
5. Bron offline/rechten veranderd tijdens wachten/model verdwenen: geen stale feit, geen vals succes en gerichte uitweg.
6. Titelresultaat, kijkcijfers en lange tekst in hoofdscherm én ballon: eerste focus, laatste regel, Menu, terugkeer na kaart openen.
7. Configuratie op iPhone, openen op AppleTV, wijziging terug: BIGP-KC1 blijft hardware-open.
8. Native toetsenbord/dictatie en avatar tijdens spreken, stoppen, afspelen en profielwissel; actuele screenshots bij iedere stand.

## Adviesvolgorde

Eerst F1 binnen BP-05 uitwerken en F3 native reproduceren, daarna F2 en overige herstelstanden. F4 is een kleine correctie; F5/F6 zijn afwegingen, geen verplichte scope-uitbreiding. Werk de bestaande BP-04b/05/06-volgorde af met echte vraagsets en de hierboven genoemde acceptatie. Visuele verfijning volgt op actuele standbeelden en devicecontrole; behoud de bestaande shell. De actuele roadmap van8oktober vergelijkt uitvoering met bugs, tvOS-UX en Requests2.0; de interne BP-afhankelijkheden en WIP/reviewgates blijven gelden.

## Vervolg

De begrensde implementatie en resterende poorten staan in [audit-herstel](2026-10-08-big-p-audit-herstel.md). Bovenstaande audit blijft het historische bronbeeld, geen afsluiting van de herstelronde.
