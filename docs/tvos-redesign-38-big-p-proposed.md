# Mockup 38, Big P (Pleya Assistant), voorgesteld

| Veld | Waarde |
|------|--------|
| Status | PROPOSED DESIGN TARGET |
| Goedgekeurd door | nog niet; Michel Knoop beslist |
| Datum | 2 oktober 2026 |
| Set | 38 A tot en met I: hub-ingang, geen toegang, instellen (twee beelden), rust, luisteren, werken, resultaat, bevestiging (Pleya Server en Plex) |
| In de repo | `docs/assets/tvos-unified/mockups-2026-10-02-big-p/` |
| Bron | `docs/assets/tvos-unified/src/pages/38-big-p-*.html`, gedeelde opmaak in `src/assets/bigp/bigp.css` |
| Branch | `feat/pleya-assistant-core` |

Dit is een voordracht. Tot Michel akkoord geeft is geen enkel beeld een bouwopdracht. Bij akkoord
krijgt dit bestand de naam `tvos-redesign-38-big-p-approved.md`, status APPROVED en een DEC-nummer.

## Wat vaststaat en hier niet ter discussie ligt

Het product is besloten: Big P is een beheerassistent. De beheerder spreekt een verzoek in, een
taalmodel kiest Pleya-tools, Pleya controleert de rechten, vraagt bevestiging bij gevoelige acties,
voert uit en toont het resultaat. Big P legt uit en praat; Pleya beslist en handelt. De set tekent
dat na en ontwerpt het niet opnieuw.

Gevolgen die in elk beeld terugkomen:

- De enige ingang is een tegel in Mijn Pleya, groep Pleya. Geen zwevende knop, geen roottab, geen
  overlay op andere schermen, geen chatvenster.
- Big P heeft vier standen: rust, luisteren, werken, resultaat. Er beweegt niets behalve de focus.
- Ollama en OpenRouter staan alleen op het instelscherm (38 C2). Elders heet het "AI-provider".
- Een bevestiging is een kaart van Pleya met vaste velden, geen bericht van Big P. Big P staat er
  gedimd achter en heeft er geen tekst in.

## Standen en kunst

De kunst komt ongewijzigd uit `~/.claude/skills/big-p/avatar/`, verkleind naar 560x700 in
`src/assets/bigp/`. Ze staat alleen op donkere vlakken, want de bron heeft een donkere rand.

| Stand | Kunst | Waarom deze |
|-------|-------|-------------|
| Hub-tegel, geen toegang, instellen | `bigp-blij` | Neutraal vriendelijk. Een bezorgd gezicht bij "geen toegang" zou suggereren dat er iets stuk is, en dat is niet zo. |
| Rust (38 D) | `bigp-zwaaien` | De begroeting is de enige plek waar Big P iets "doet" zonder dat er een taak loopt. |
| Luisteren (38 E) | `bigp-verrast` | Open mond en grote ogen lezen op afstand als "ik let op". Kleiner getekend, zodat het toetsenbord ruimte heeft. |
| Werken (38 F) en achter de bevestiging (38 H, I) | `bigp-vinger_presenteren` | Een stilstaande houding die "momentje" zegt, zonder draaiend wiel of animatie. |
| Resultaat (38 G) | `bigp-duim_presenteren` | Duim omhoog plus een open hand naar de resultaatkaart: de figuur wijst naar wat Pleya deed. |

Bij een mislukte actie is `bigp-bezorgd` de logische kunst. Die stand is niet getekend, zie de open
vragen.

## De beelden

| Nr | Bestand | Wat het beslist | Focus bij openen |
|----|---------|-----------------|------------------|
| 38 A | 38-big-p-a.png | Big P is een gewone hub-tegel in de groep Pleya, op plek twee na Instellingen. In plaats van een lijnicoon draagt hij een klein portret van Big P rechts in de tegel. Ondertitel "Beheer Pleya met je stem". Uitloggen schuift naar een tweede rij onder de vouw. De rest van de hub volgt `buildTvMyPleyaGroups` en de Nederlandse teksten uit `nl.i18n.json`. | Big P-tegel (getekend als de gefocuste tegel; bij binnenkomst geldt de bestaande hubregel) |
| 38 B | 38-big-p-b.png | Beheerder zonder toegang. Big P staat er wel, met een korte uitleg en de zin dat je hem hier niet kunt aanzetten of kopen. Geen vraagknop, geen prijs, geen link naar een winkel. | "Terug naar Mijn Pleya", de enige knop |
| 38 C1 | 38-big-p-c1.png | Geen provider ingesteld. De letterlijke zin uit de opdracht als kop, één zin over wie wat doet, en "Big P instellen" als primaire actie. | "Big P instellen" |
| 38 C2 | 38-big-p-c2.png | Providerkeuze als drie gewone rijen: Ollama-server, Ollama Cloud, OpenRouter. Rechts staat wat je daarna nodig hebt (adres of API-sleutel). Onder de rijen staat welke gegevens naar de provider gaan en dat wachtwoorden en tokens in Pleya blijven. | Ollama-server, omdat dat de enige keuze is waarbij je vragen thuis blijven |
| 38 D | 38-big-p-d.png | Rust. Statusregel met de servers waarop Big P kan handelen, een begroeting, één primaire knop "Vraag Big P" en drie voorbeeldvragen als gewone focusbare knoppen. Een voorbeeld kiezen stuurt die vraag meteen. | "Vraag Big P" |
| 38 E | 38-big-p-e.png | Luisteren gebeurt in het systeemtoetsenbord van tvOS met dicteren, onderaan over het scherm. Pleya tekent geen eigen microfoonscherm. Big P staat kleiner in de luisterstand met "Ik luister". | Bepaalt tvOS |
| 38 F | 38-big-p-f.png | Werken. De vraag staat er letterlijk boven, daaronder één statusregel "Bezig met je vraag…". Geen voortgangsbalk, geen tussenstappen. Annuleren is de enige knop. | "Annuleren" |
| 38 G | 38-big-p-g.png | Resultaat. Big P geeft een antwoord van één zin plus één zin uitleg. Daaronder staat een kaart van Pleya ("Uitgevoerd door Pleya · tijd") met per actie een regel: "Scan gestart · Films · Zolder". Daarna "Nog een vraag" en "Klaar". | "Nog een vraag" |
| 38 H | 38-big-p-h.png | Bevestiging, Pleya Server. Pleya-kaart "Gebruiker aanmaken" met gebruiker, server, toegang en een afgeschermd wachtwoordveld. Aanmaken is uitgeschakeld tot het wachtwoord is ingevuld. De kleine letters zeggen dat het wachtwoord niet naar Big P en niet naar de AI-provider gaat. | "Annuleren" |
| 38 I | 38-big-p-i.png | Dezelfde kaart voor Plex, zonder wachtwoordveld: een beheerde Home-gebruiker heeft geen eigen login, en een pincode instellen zit niet in deze ronde. Aanmaken is meteen bruikbaar. De kleine letters zeggen wat er op Plex echt ontstaat: "Beheerde Plex Home-gebruiker, met een share op deze server." | "Annuleren" |

## Waarom Annuleren de standaardfocus is

Een bevestiging komt direct na het dicteren. De Select-druk waarmee je het toetsenbord afsluit
("Gereed") ligt dan nog in je duim, en op tvOS is een tweede druk zo gegeven. Staat de focus op
Aanmaken, dan maakt één onbedoelde druk een account aan dat je daarna moet opruimen. Staat hij op
Annuleren, dan kost diezelfde vergissing alleen het opnieuw stellen van de vraag. Aanmaken ligt één
stap naar rechts: dat is een bewuste handeling, en precies dat wil een gevoelige actie.

In 38 H is de volgorde in de praktijk: Annuleren (focus) of omhoog naar het wachtwoordveld,
wachtwoord invullen in het systeemtoetsenbord, terug naar rechts naar Aanmaken.

## Wat deze set niet beslist

- De functionele specificatie van tools, rechten of welke acties als gevoelig gelden. Het beeld
  toont één voorbeeld per soort.
- Hoe toegang (de entitlement) wordt vastgesteld en waar die vandaan komt.
- Of niet-beheerders de tegel zien. De voordracht gaat ervan uit dat de tegel voor hen ontbreekt,
  zoals Activiteit ontbreekt zonder bron. Getekend is alleen de beheerder.
- De invulschermen na 38 C2 (serveradres, API-sleutel, modelkeuze, verbindingstest).
- Foutstanden: provider onbereikbaar, geen rechten voor deze actie, actie mislukt.
- Een gesprek over meerdere beurten. De set gaat uit van één vraag, één uitkomst.
- iOS, iPad en desktop.
- De exacte vorm van het tvOS-toetsenbord. 38 E is een benadering; het echte toetsenbord tekent
  tvOS zelf, en de compositie geldt alleen voor wat Pleya eromheen tekent.

## Open vragen voor Michel

1. **Plek van de tegel.** Na Instellingen (getekend) of als eerste in de groep Pleya? Op plek twee
   blijft Instellingen waar het nu staat; op plek één is Big P de eerste tegel die je in de groep
   raakt. In beide gevallen schuift Uitloggen naar een tweede rij.
2. **Portret in de tegel.** De Big P-tegel is de enige hub-tegel met kunst in plaats van een
   icoon. Akkoord, of liever een lijnicoon zoals de rest en Big P pas op het scherm zelf?
3. **Label van de primaire knop.** "Vraag Big P" met microfoonicoon (getekend) of "Spreek je vraag
   in"? Het systeemtoetsenbord laat ook typen toe, dus "Spreek" belooft alleen de helft.
4. **Voorbeeldvragen.** Vast drietal, of drie die Pleya kiest op basis van wat er op de servers
   speelt (bijvoorbeeld "Welke taken zijn mislukt?" alleen als er een mislukte taak is)?
5. **Foutstand.** Moet `bigp-bezorgd` als vijfde stand bij "actie mislukt", of blijft het bij vier
   standen en draagt de Pleya-kaart de fout met een rode status?
6. **Kaart bij meerdere acties.** Bij "Maak Sam aan en geef hem toegang tot Kids" zijn het twee
   acties. Eén bevestigingskaart voor het geheel (getekend) of één per actie?
7. **Annuleren tijdens werken.** Kan Pleya een al gestarte servertaak terugdraaien, of betekent
   Annuleren in 38 F alleen "stop met wachten op het model"? Dat bepaalt of de knop er mag staan
   nadat een actie is begonnen.

## De beelden, hashes

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 38 A | 38-big-p-a.png | `a72f10c9bac2d6b253e4964e4597bd6be2e6330624d95827fd9478052a9ce7f8` |
| 38 B | 38-big-p-b.png | `4d75b1277c8bd91fbcbe8d201bf5934dd8e7522ee6eb0eb9b59e0cab893432ac` |
| 38 C1 | 38-big-p-c1.png | `47bcea3eb61579e24a0e8be8e68d519106e8a7a7cb213584c8043a108b57a427` |
| 38 C2 | 38-big-p-c2.png | `da775770dbebee4afa112107cecd587dd121fdda0840ecc6872362faf9a23964` |
| 38 D | 38-big-p-d.png | `dcdc7db885c71248dbe60406a2e378d2d6278593e2b0ca2dbc6363d0f8053475` |
| 38 E | 38-big-p-e.png | `895442766636bc01c3d5a35ce9093f6e5b562f67a3b0650e2cbb4581f61d3268` |
| 38 F | 38-big-p-f.png | `c51f2ccb5d2f8791022249c292b1ec30d55deedec60a16ee32de3975d3fbc17d` |
| 38 G | 38-big-p-g.png | `712aa0986c3d97f496f89c608e27237c1772d0ccc90f0475cd3ef5443022bfc1` |
| 38 H | 38-big-p-h.png | `a1ce8caa0f02ac65c1d566e84791430e241c747157f0e96c534316e0559e3bdb` |
| 38 I | 38-big-p-i.png | `8803f43bf6000ca0c6bb0ecdd49859963482a94478a510bc0eb6fef65de41d56` |

Herschieten: `cd docs/assets/tvos-unified/src && PLEYA_MOCKUP_DEST=$PWD/../mockups-2026-10-02-big-p node build.mjs 38-big-p`.
Een andere pixel betekent een andere hash; werk dan deze tabel bij.

## Wanneer er opnieuw akkoord nodig is

Dezelfde vier gevallen als bij 09 tot en met 37: een andere compositie dan het beeld tekent, een
componentfamilie die niet in de set voorkomt, een dichtheid die van de getekende afwijkt, en een
gedragswijziging die het beeld niet kan tonen maar die een eerder productbesluit raakt. Voor Big P
komt daar een vijfde bij: elke plek buiten Mijn Pleya waar Big P zichtbaar wordt.
