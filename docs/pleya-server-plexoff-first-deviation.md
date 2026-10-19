# Roadmap deviation proposal: Plex-off eerst, boeken en web-consumer erna

**Status:** voorstel, wacht op Michels goedkeuring. Niets hieronder is doorgevoerd.
**Datum:** 2026-10-19
**Raakt:** `docs/PLEYA-SERVER-MASTERLIST.md` hoofdstuk 2, `docs/pleya-server-rebaseline/I-master-implementation-plan.md` (volgorde), de protocolvensters 3 tot en met 8 uit deel J.
**Besluiten eronder:** [DEC-150](DECISIONS.md) (volgorde), [DEC-151](DECISIONS.md) (werkwijze en venster per golf).

Format volgens hoofdstuk 23.1 van `pleya-server-architecture.md`.

## 1. De oorspronkelijke aanname

De re-baseline van 4 september 2026 zet alle productscope in één afhankelijkheidsgraaf en loopt die
in acht golven af: eerst boeken (S3, S6), de webconsumer en het beheer-web (S8 tot S13), dan de
clients, dan afspelen op eigen kracht. De aanname was dat de volgorde er niet toe doet zolang elke
afhankelijkheid wordt gerespecteerd, en dat het hele pakket in één traject naar de Plex-off gate
(`PLEX_OFFLINE_REPLACEMENT_GATE`, `PLEYA-SERVER-REPLACEMENT-MATRIX.md:502`) gaat.

## 2. De nieuwe bevinding

Gemeten op 19 oktober 2026: 150 taken, 23 gereed, 7 bezig, 120 open. De kritieke lijn naar de gate
loopt door boeken en leesvoortgang (`S1 → S3 → S5 en S6 → S14 → S17 → S18 → S23 → S15`), terwijl
de gate zelf over film en serie gaat. Boeken, de webconsumer, de setup-wizard, de browserspeler en
de MCP-laag staan op de lijn omdat de graaf ze zo koppelt, niet omdat een gatecategorie ze eist.
Er draait ondertussen al een oudere stand op `web.pleya.app`, dus een instance die beter wordt is
haalbaar. Het proces kost daarbij te veel: de subagentcyclus met ledger in `.superpowers/sdd/`
verbruikt per taak meer tokens dan het werk zelf.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

Twee dingen kloppen niet meer. De volgorde stelt het afvinken van contentdomeinen boven het bereiken
van het eindpunt waar Michel naartoe werkt (Plex uit op de NAS). En het protocolvenster per slice
(acht vensters, elk met eigen open- en sluit-DEC) is voor de resterende werkvolgorde meer ceremonie
dan bescherming: de zes compatibiliteitsregels en `scripts/check_protocol.sh` vangen de echte
risico's, en dat blijft zo bij een venster per golf.

## 4. De voorgestelde wijziging

**Volgorde.** Eerst de kritieke lijn voor de gate, in vijf golven plus een slot:

| Golf | Taken | Levert op |
| --- | --- | --- |
| A | S2.6, S2.7 | S2 en venster 2 dicht, eerste NAS-deploy van de s25-stand |
| B | S4.1 tot 4.4 en 4.6, S5.1 tot 5.3 en 5.5, S22.1 tot 22.5 en 22.7 tot 22.9 | catalogus compleet: `.nfo`, artworkladder, TMDB-match en artwork, filters, facetten, zoeken |
| C | S17, S18, S14.1 tot 14.3 en 14.5 | PlaybackPlan, transcode en remux met hw-accel, de app op het contract |
| D | S20.1 tot 20.3 en 20.5 tot 20.6, S23.1 tot 23.3 en 23.5 | geschiedenis, favorieten, spoorvoorkeuren, downloads en sync-back |
| E | S7 afmaken, S10, S24, S25 | beheer-web, remote hardening, back-up en restore |
| slot | S15.1, 15.2 (journeys binnen scope), 15.3, 15.5, 15.6, 15.7 | Plex-off gate groen, merge naar `main`, NAS uitgerold |

**Venster per golf.** Venster 2 sluit in golf A zoals gepland (S2.6). Elke volgende golf die het
protocol raakt, opent één venster met één DEC en sluit het met één DEC. Rijen die nu in
S3, S6, S8, S12, S19 en S21 zitten gaan mee naar de vensters ná de gate; ze verdwijnen niet.

**Proces.** Inline werk in één sessie per golf in de s25-worktree, per taak code, test en
masterlijstregel in één commit, per slice één `/code-review` op medium. Na elke golf een NAS-deploy.

## 5. Gevolgen voor latere fasen

Alles wat nu uitgesteld wordt staat op `[!]` met verwijzing naar dit document en start pas na de
gate: S3, S6, S9, S12 (boeken, PS-14 en PS-15), S8 (webconsumer), S11 (wizard), S13 (browserspeler),
S16 (MCP), S19, S21, plus S4.5, S5.4, S14.4, S14.6, S20.4, S22.6, S23.4, S15.4 en S15.8. PS-12 blijft
een apart besluit na S15.

Twee afhankelijkheden die ik in golf C en D moet controleren in plaats van aannemen: de graaf zet
S14 achter S3, S5 en S6, en S20 achter S6. Mijn aanname is dat de in-scope taken (capabilities,
filterstubs, favorieten, geschiedenis) geen boekenschema nodig hebben. Blijkt een taak toch een
tabel uit S3 of S6 te eisen, dan is dat een architectuurblocker en stop ik met een melding.

Het locatorbesluit P5 (S6.1) blijft open en blokkeert in dit traject niets. Boeken blijven
productscope ([DEC-093](DECISIONS.md)); de `media_*`-tabellen blijven audiovisueel.

## 6. Welke scope hierdoor vervalt

Geen enkele. Alles wat uitgesteld is blijft productscope en krijgt zijn vrijgave na de gate. Wat
wel vervalt is de eis dat boeken, webconsumer en browserspeler af zijn vóór de eerste Plex-off
gate. De gate-categorie Migratie blijft in S15.5 als keuze staan; PS-12 is een apart besluit.
Streaming-updates (S21) vallen in dit traject terug op polling, wat voor "degradeert netjes" volstaat.

## Stopcriterium

Dit voorstel is geen vrijgave. Pas na Michels akkoord start golf A. Wordt het afgewezen, dan blijft
S2.6 de eerstvolgende taak in de bestaande volgorde en verandert alleen het werkproces niet.
