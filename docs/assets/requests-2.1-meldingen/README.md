# Requests 2.1: meldingen en notificaties (voorstel)

**Status: VOORSTEL, 9 november 2026.** Nog niet goedgekeurd.

Roadmap: A-20 (ontwerp) en A-21 (implementatie).

Deze set vult de goedgekeurde set [Requests 2.0](../requests-2.0/README.md) aan. Die set blijft leidend en is niet aangeraakt.

Familie 10 (Probleem melden) is nieuwe scope. Ze wacht op een besluit van Michel en staat als open beslispunt in [de roadmap](../../ROADMAP.md).

Bekijken:
- de beelden: [index.html](index.html)
- wat de app nu anders doet dan goedgekeurd: [AFWIJKINGEN.md](AFWIJKINGEN.md)
- dezelfde gegevens machineleesbaar: [manifest.json](manifest.json)

## Wat er ligt

29 staten in vier families, telkens voor TV, telefoon, tablet en desktop. Dat zijn 82 beelden. De maten en borden zijn dezelfde als in Requests 2.0.

| Familie | Inhoud | Tegenover main |
|---|---|---|
| 9. Meldingen afhandelen | lijst Open/Opgelost, leeg, niet beschikbaar, fout, gesprek, reageren, onbevestigd, opgelost, bevestigen, menu | Lijst en gesprek bestaan op PR #654 (alleen iPhone). De vorm hier is nieuw |
| 10. Probleem melden | ingang op de titelpagina en in de speler, type, seizoen en aflevering, toelichting, verstuurd, al gemeld, geen recht, fout | Nieuw, nergens gebouwd |
| 11. Notificaties | centrum, leeg, voorkeuren, uitleg voor de systeemvraag, geweigerd, pushvoorbeelden, server zonder push | Categorieën en push staan op de WIP-commit `5c5c284`. Geweigerd, uitleg en zonder push zijn nieuw |
| 12. Ingangen | Mijn Pleya met Meldingen en Notificaties, snelkoppeling naar Meldingen voor beheerders | Nieuw |

## Keuzes in dit voorstel

1. **Woorden.** "Meldingen" betekent Seerr-issues. "Notificaties" zijn de updates aan de gebruiker. Dit volgt de vertalingen op de branches (`seerrIssues`, `pleyaNotifications`). De typen heten Beeld, Geluid, Ondertiteling en Overig.
2. **Een melding ziet eruit als een aanvraag.** Rijen staan in één kaart, met dezelfde capsule met stip en dezelfde sheets. Er komen geen nieuwe kleuren bij. Rood blijft voor de gekozen chip, de ongelezen-stip en de teller.
3. **Gesprek als berichten.** De beheerder staat rechts. Opgelost en heropend verschijnen als gebeurtenis in het gesprek.
4. **Herstel na een onbevestigde reactie (9H).** Pleya ververst eerst het gesprek en biedt niet blind opnieuw plaatsen aan. Dit is hetzelfde patroon als 4I en 8J.
5. **Melden vanuit de speler neemt context mee.** Het tijdstip, de audiotrack en het seizoen of de aflevering gaan automatisch mee. Het tekstvak is optioneel.
6. **Al gemeld (10G).** Pleya stuurt eerst naar de bestaande melding. Apart melden blijft mogelijk.
7. **Notificaties staan standaard uit en zijn per categorie te kiezen.** Beheercategorieën zie je alleen als beheerder. Push loopt via de eigen Pleya Server, zoals in de WIP.
8. **TV is eerlijk over push.** tvOS toont geen systeemmeldingen. Op TV staan notificaties in Mijn Pleya, en een kaart in de app pakt nooit de focus.
9. **Ingangen.** Mijn Pleya krijgt de rijen Meldingen en Notificaties met een teller. Beheerders zien open meldingen boven de aanvraaglijst. Op TV is dat een filterchip.

## Opnieuw genereren

```
cd docs/assets/requests-2.1-meldingen/src && node gen.mjs
```

- Optie `--no-render` werkt alleen manifest, index en matrix bij.
- Een filter op een deel van de bestandsnaam rendert alleen die beelden.
- De generator controleert dat:
  - er geen emdash in de copy staat
  - 9H herstelt door eerst te verversen
  - er geen kapotte afbeeldingen zijn
  - knoppen en focus binnen beeld vallen
  - regels in rijen niet worden afgekapt

## Dekkingsmatrix

<!-- MATRIX:BEGIN -->
### 9. Meldingen afhandelen

| Code | Staat | Rol | Tegenover main | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 9A | Open meldingen | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9A-open-meldingen.jpg) | [paneel 9A](phone/mk-ph-9A-9D-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9A-open-meldingen.jpg) | [beeld](desktop/mk-dk-9A-open-meldingen.jpg) |
| 9B | Filter Opgelost | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9B-filter-opgelost.jpg) | [paneel 9B](phone/mk-ph-9A-9D-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9B-filter-opgelost.jpg) | [beeld](desktop/mk-dk-9B-filter-opgelost.jpg) |
| 9C | Mijn meldingen leeg | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-9C-mijn-meldingen-leeg.jpg) | [paneel 9C](phone/mk-ph-9A-9D-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9C-mijn-meldingen-leeg.jpg) | [beeld](desktop/mk-dk-9C-mijn-meldingen-leeg.jpg) |
| 9D | Niet beschikbaar op deze server | aanvrager | deels op een open branch, niet op main | [beeld](tv/mk-tv-9D-niet-beschikbaar-op-deze-server.jpg) | [paneel 9D](phone/mk-ph-9A-9D-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9D-niet-beschikbaar-op-deze-server.jpg) | [beeld](desktop/mk-dk-9D-niet-beschikbaar-op-deze-server.jpg) |
| 9E | Fout bij ophalen | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9E-fout-bij-ophalen.jpg) | [paneel 9E](phone/mk-ph-9E-9H-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9E-fout-bij-ophalen.jpg) | [beeld](desktop/mk-dk-9E-fout-bij-ophalen.jpg) |
| 9F | Detail met gesprek | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9F-detail-met-gesprek.jpg) | [paneel 9F](phone/mk-ph-9E-9H-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9F-detail-met-gesprek.jpg) | [beeld](desktop/mk-dk-9F-detail-met-gesprek.jpg) |
| 9G | Reactie typen | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9G-reactie-typen.jpg) | [paneel 9G](phone/mk-ph-9E-9H-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9G-reactie-typen.jpg) | [beeld](desktop/mk-dk-9G-reactie-typen.jpg) |
| 9H | Reactie niet bevestigd | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9H-reactie-niet-bevestigd.jpg) | [paneel 9H](phone/mk-ph-9E-9H-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9H-reactie-niet-bevestigd.jpg) | [beeld](desktop/mk-dk-9H-reactie-niet-bevestigd.jpg) |
| 9I | Opgelost, heropenen mogelijk | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-9I-opgelost-heropenen-mogelijk.jpg) | [paneel 9I](phone/mk-ph-9I-9K-meldingen-afhandelen.jpg) | [beeld](tablet/mk-tb-9I-opgelost-heropenen-mogelijk.jpg) | [beeld](desktop/mk-dk-9I-opgelost-heropenen-mogelijk.jpg) |
| 9J | Oplossen bevestigen | beheerder | nieuw, niet gebouwd | [paneel 9J](tv/mk-tv-9J-9K-meldingen-afhandelen.jpg) | [paneel 9J](phone/mk-ph-9I-9K-meldingen-afhandelen.jpg) | [paneel 9J](tablet/mk-tb-9J-9K-meldingen-afhandelen.jpg) | [paneel 9J](desktop/mk-dk-9J-9K-meldingen-afhandelen.jpg) |
| 9K | Acties via de drie puntjes | beheerder | nieuw, niet gebouwd | [paneel 9K](tv/mk-tv-9J-9K-meldingen-afhandelen.jpg) | [paneel 9K](phone/mk-ph-9I-9K-meldingen-afhandelen.jpg) | [paneel 9K](tablet/mk-tb-9J-9K-meldingen-afhandelen.jpg) | [paneel 9K](desktop/mk-dk-9J-9K-meldingen-afhandelen.jpg) |

### 10. Probleem melden

| Code | Staat | Rol | Tegenover main | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 10A | Ingang op de titelpagina | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-10A-ingang-op-de-titelpagina.jpg) | [paneel 10A](phone/mk-ph-10A-10D-probleem-melden.jpg) | [beeld](tablet/mk-tb-10A-ingang-op-de-titelpagina.jpg) | [beeld](desktop/mk-dk-10A-ingang-op-de-titelpagina.jpg) |
| 10B | Ingang in de speler | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-10B-ingang-in-de-speler.jpg) | [paneel 10B](phone/mk-ph-10A-10D-probleem-melden.jpg) | [beeld](tablet/mk-tb-10B-ingang-in-de-speler.jpg) | [beeld](desktop/mk-dk-10B-ingang-in-de-speler.jpg) |
| 10C | Type kiezen | aanvrager | nieuw, niet gebouwd | [paneel 10C](tv/mk-tv-10C-10D-probleem-melden.jpg) | [paneel 10C](phone/mk-ph-10A-10D-probleem-melden.jpg) | [paneel 10C](tablet/mk-tb-10C-10E-probleem-melden.jpg) | [paneel 10C](desktop/mk-dk-10C-10E-probleem-melden.jpg) |
| 10D | Serie: seizoen en aflevering | aanvrager | nieuw, niet gebouwd | [paneel 10D](tv/mk-tv-10C-10D-probleem-melden.jpg) | [paneel 10D](phone/mk-ph-10A-10D-probleem-melden.jpg) | [paneel 10D](tablet/mk-tb-10C-10E-probleem-melden.jpg) | [paneel 10D](desktop/mk-dk-10C-10E-probleem-melden.jpg) |
| 10E | Toelichting | aanvrager | nieuw, niet gebouwd | [paneel 10E](tv/mk-tv-10E-10F-probleem-melden.jpg) | [paneel 10E](phone/mk-ph-10E-10H-probleem-melden.jpg) | [paneel 10E](tablet/mk-tb-10C-10E-probleem-melden.jpg) | [paneel 10E](desktop/mk-dk-10C-10E-probleem-melden.jpg) |
| 10F | Verstuurd | aanvrager | nieuw, niet gebouwd | [paneel 10F](tv/mk-tv-10E-10F-probleem-melden.jpg) | [paneel 10F](phone/mk-ph-10E-10H-probleem-melden.jpg) | [paneel 10F](tablet/mk-tb-10F-10H-probleem-melden.jpg) | [paneel 10F](desktop/mk-dk-10F-10H-probleem-melden.jpg) |
| 10G | Al gemeld door iemand anders | aanvrager | nieuw, niet gebouwd | [paneel 10G](tv/mk-tv-10G-10H-probleem-melden.jpg) | [paneel 10G](phone/mk-ph-10E-10H-probleem-melden.jpg) | [paneel 10G](tablet/mk-tb-10F-10H-probleem-melden.jpg) | [paneel 10G](desktop/mk-dk-10F-10H-probleem-melden.jpg) |
| 10H | Geen recht om te melden | profiel zonder recht | nieuw, niet gebouwd | [paneel 10H](tv/mk-tv-10G-10H-probleem-melden.jpg) | [paneel 10H](phone/mk-ph-10E-10H-probleem-melden.jpg) | [paneel 10H](tablet/mk-tb-10F-10H-probleem-melden.jpg) | [paneel 10H](desktop/mk-dk-10F-10H-probleem-melden.jpg) |
| 10I | Versturen mislukt, tekst blijft | aanvrager | nieuw, niet gebouwd | [paneel 10I](tv/mk-tv-10I-10I-probleem-melden.jpg) | [paneel 10I](phone/mk-ph-10I-10I-probleem-melden.jpg) | [paneel 10I](tablet/mk-tb-10I-10I-probleem-melden.jpg) | [paneel 10I](desktop/mk-dk-10I-10I-probleem-melden.jpg) |

### 11. Notificaties

| Code | Staat | Rol | Tegenover main | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 11A | Notificatiecentrum | aanvrager | deels op een open branch, niet op main | [beeld](tv/mk-tv-11A-notificatiecentrum.jpg) | [paneel 11A](phone/mk-ph-11A-11D-notificaties.jpg) | [beeld](tablet/mk-tb-11A-notificatiecentrum.jpg) | [beeld](desktop/mk-dk-11A-notificatiecentrum.jpg) |
| 11B | Leeg, alles staat uit | aanvrager | deels op een open branch, niet op main | [beeld](tv/mk-tv-11B-leeg-alles-staat-uit.jpg) | [paneel 11B](phone/mk-ph-11A-11D-notificaties.jpg) | [beeld](tablet/mk-tb-11B-leeg-alles-staat-uit.jpg) | [beeld](desktop/mk-dk-11B-leeg-alles-staat-uit.jpg) |
| 11C | Voorkeuren per categorie | beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-11C-voorkeuren-per-categorie.jpg) | [paneel 11C](phone/mk-ph-11A-11D-notificaties.jpg) | [beeld](tablet/mk-tb-11C-voorkeuren-per-categorie.jpg) | [beeld](desktop/mk-dk-11C-voorkeuren-per-categorie.jpg) |
| 11D | Uitleg voor de systeemvraag | aanvrager | nieuw, niet gebouwd | [paneel 11D](tv/mk-tv-11D-11D-notificaties.jpg) | [paneel 11D](phone/mk-ph-11A-11D-notificaties.jpg) | [paneel 11D](tablet/mk-tb-11D-11D-notificaties.jpg) | [paneel 11D](desktop/mk-dk-11D-11D-notificaties.jpg) |
| 11E | Push geweigerd | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-11E-push-geweigerd.jpg) | [paneel 11E](phone/mk-ph-11E-11G-notificaties.jpg) | [beeld](tablet/mk-tb-11E-push-geweigerd.jpg) | [beeld](desktop/mk-dk-11E-push-geweigerd.jpg) |
| 11F | Voorbeelden van push | aanvrager en beheerder | deels op een open branch, niet op main | [beeld](tv/mk-tv-11F-voorbeelden-van-push.jpg) | [paneel 11F](phone/mk-ph-11E-11G-notificaties.jpg) | [beeld](tablet/mk-tb-11F-voorbeelden-van-push.jpg) | [beeld](desktop/mk-dk-11F-voorbeelden-van-push.jpg) |
| 11G | Server zonder push | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-11G-server-zonder-push.jpg) | [paneel 11G](phone/mk-ph-11E-11G-notificaties.jpg) | [beeld](tablet/mk-tb-11G-server-zonder-push.jpg) | [beeld](desktop/mk-dk-11G-server-zonder-push.jpg) |

### 12. Ingangen

| Code | Staat | Rol | Tegenover main | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 12A | Mijn Pleya met Meldingen en Notificaties | aanvrager | nieuw, niet gebouwd | [beeld](tv/mk-tv-12A-mijn-pleya-met-meldingen-en-notificaties.jpg) | [paneel 12A](phone/mk-ph-12A-12B-ingangen.jpg) | [beeld](tablet/mk-tb-12A-mijn-pleya-met-meldingen-en-notificaties.jpg) | [beeld](desktop/mk-dk-12A-mijn-pleya-met-meldingen-en-notificaties.jpg) |
| 12B | Aanvragen met snelkoppeling naar Meldingen | beheerder | nieuw, niet gebouwd | [beeld](tv/mk-tv-12B-aanvragen-met-snelkoppeling-naar-meldingen.jpg) | [paneel 12B](phone/mk-ph-12A-12B-ingangen.jpg) | [beeld](tablet/mk-tb-12B-aanvragen-met-snelkoppeling-naar-meldingen.jpg) | [beeld](desktop/mk-dk-12B-aanvragen-met-snelkoppeling-naar-meldingen.jpg) |
<!-- MATRIX:END -->
