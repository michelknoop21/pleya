# Aanvragen, meldingen en notificaties: drie richtingen

**Status: GEKOZEN, 9 november 2026.** Michel koos richting C, Regiekamer ([DEC-XXX](../../DECISIONS.md)). A en B zijn niet gekozen en blijven alleen als referentie staan.

Roadmap: A-20.

Michel vond zowel de huidige app als de goedgekeurde set [Requests 2.0](../requests-2.0/README.md) en de aanvulling [meldingen en notificaties](../requests-2.1-meldingen/README.md) niet goed genoeg. Deze ronde laat drie duidelijk verschillende richtingen zien.

Elke richting toont dezelfde vier telefoonschermen en één Apple TV-scherm, zodat je ze direct naast elkaar kunt leggen. De gekozen richting wordt daarna uitgewerkt tot een volledige set met alle staten en platforms.

| Richting | Idee | Telefoon | TV |
|---|---|---|---|
| **A. Affiche** | Posters voorop, zoals Home. De status staat op de poster en een download is een rode voortgangslijn, net als kijkvoortgang. Meldingen tonen het beeld waar het misging. Notificaties zijn grote kaarten met Afspelen | [A1 tot en met A4](richting-A-affiche-telefoon.jpg) | [A5](richting-A-affiche-tv.jpg) |
| **B. Tijdlijn** | Elke aanvraag is een zending met vier stappen: aangevraagd, goedgekeurd, downloaden, beschikbaar. Een melding loopt als tijdlijn met de reacties erin. Aanvragen, meldingen en bibliotheek komen samen in één Activiteit | [B1 tot en met B4](richting-B-tijdlijn-telefoon.jpg) | [B5](richting-B-tijdlijn-tv.jpg) |
| **C. Regiekamer** | Compact en beheer eerst: tellers bovenaan, een wachtrij met de oudste eerst, meerdere tegelijk goedkeuren en vegen. Meldingen krijgen snelle antwoorden. Per onderwerp kies je Direct, Samenvatting of Uit | [C1 tot en met C4](richting-C-regiekamer-telefoon.jpg) | [C5](richting-C-regiekamer-tv.jpg) |

Alleen de aanvragenlijst van de drie richtingen naast elkaar: [vergelijking](vergelijking-aanvragenlijst.jpg).

Alle drie gebruiken de Pleya-tokens (`#141414`, rood alleen als accent, Inter) en de bestaande tabbalk en topnavigatie. Mengen kan ook. Bijvoorbeeld: de lijst uit A met de tijdlijn uit B als detail, en de samenvatting uit C bij notificaties.

Opnieuw genereren: `cd docs/assets/requests-richtingen/src && node gen.mjs`.
