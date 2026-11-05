# Webbundel vervangen bij deploy

5 november 2026. Roadmap: C-05, S25.8. Eigenaar: Michel Knoop.
Unified-impact: geen wijziging in itemidentiteit, kijkstatus of bronselectie.

`pleya_server/deploy-nas.sh` pakte nieuwe bronnen over de bestaande webbundel uit.
Bestanden die uit de nieuwe build waren verdwenen, bleven daardoor in de volgende image zitten.
Het script ontvangt en controleert nu eerst het archief, inclusief de aanwezigheid van
`internal/web/dist/index.html`. De vorige bundel verhuist tijdelijk voordat de nieuwe wordt
uitgepakt. Een extractiefout zet de vorige bundel terug en stopt vóór de containerbuild.
Als terugzetten zelf mislukt, blijft de tijdelijke map met de vorige bundel behouden.

Lokaal bewijs:

- `python3 pleya_server/scripts/test_deploy_env_readers.py`: OK, 13 synthetische gevallen met echte tar-archieven en lokale SSH-stubs. Controleert verdwenen chunks, behoud van `.env`, beschadigd archief, ontbrekende index, extractiefout en eerste deploy.
- Negatieve controle met het oorspronkelijke deployscript: FAILED, 9 regressies in de eerste 11 gevallen.
- `sh pleya_server/scripts/test-deploy-root.sh`: PASS, 6 padkeuzes en 11 afwijzingen.
- `sh -n`, `shellcheck --severity=error` en `git diff --check`: exit 0.
- `scripts/ci_checks.sh`, via SSD-startcontrole en gedeelde wachtrij: All checks passed. De optionele boombrede lintercontroles zijn overgeslagen volgens de standaardinstelling.
- Onafhankelijke diffreview en controle van de laatste testwijzigingen: geen open bevindingen.

Bewijsbestanden en het oorspronkelijke script staan in de taakmap
`/Volumes/SSD/Codex/tasks/pleya-server-deploy-assets-evidence/`.
De werkmap is `/Volumes/SSD/Codex/worktrees/pleya-server-deploy-assets`, branch
`fix/server-deploy-stale-assets`, vanaf `80c372424`. Er is geen clientreleasebuild gemaakt.

Na de expliciete deployopdracht is productie op 5 november om 10:33 CET bijgewerkt via
`ssd-dev`, de normale gedeelde wachtrij en het aangepaste deployscript. Vooraf waren alle
398 Go-bronbestanden en alle build-/composebestanden gelijk aan de NAS-versie.
Er zijn geen nieuwe migraties uitgerold.

Bij de nacontrole draaide de container image `48f2522f1c66`, met status `running` en gezondheid `healthy`.
`/readyz`, `/healthz` en `/` gaven HTTP 200. De deploymap ging van 324 naar 203 bestanden;
alle 203 zijn bytegelijk aan de lokale build. Ook de live geserveerde `index.html` en
`_app/immutable/entry/app.DGE8w8YH.js` zijn bytegelijk. Schema 34, de aantallen gebruikers (1)
en kijkstatussen (12), en de hash van `.env` zijn gelijk gebleven. De tijdelijke uploadmap is weg.

Het terugvalpunt staat op de NAS in
`/volume1/pleya-private/pleya-server-before-assets-20261105-k8qIFQ` (9,1 MB):
database-dump met gecontroleerde inhoudslijst, configuratiearchief en bron-/envarchief.
De vorige image is behouden als `pleya-server-rollback:assets-20261105-103114`.
De deploy- en nacontrolelogs staan in de hierboven genoemde bewijsmap; deze bestanden en
de werkmap blijven onder beheer van Michel Knoop bewaard.

Een volledige ingelogde gebruikersflow, SSH-afbreking,
gelijktijdige deploys en een fout bij het terugplaatsen van de vorige bundel zijn niet getest.
