# Gebundelde lettertypen

Wat hier staat wordt in de app gebakken en gaat dus mee naar de App Store. Voor elk bestand hoort
hieronder te staan waar het vandaan komt, welke versie het is, onder welke licentie het valt en
welke controle daarop gedaan is. Een lettertype zonder zo'n regel hoort hier niet.

## Literata (leesletter van de reader)

`Literata-Variable.ttf` is de standaard serif van de e-book-reader. Vastgelegd bij golden 07,
revisie B; de reden staat in `docs/assets/ebooks/northstar/README.md`. Systeem-Georgia was het
alternatief en is afgewezen omdat golden en app dan niet dezelfde glyphmetriek hebben, iPhone en
iPad niet dezelfde snit, en een OS-update stil de bladspiegel van een pagina verandert.

| | |
| --- | --- |
| Familie | Literata, versie 3.103 (`gftools[0.9.29]`) |
| Ontwerper | TypeTogether |
| Herkomst | `google/fonts`, pad `ofl/literata/Literata[opsz,wght].ttf` |
| Bovenstrooms | `googlefonts/literata`, commit `0c2761b727a1b3a7cffd313c37f0f5163dfc7a63`, bestand `fonts/variable/Literata[opsz,wght].ttf` |
| Licentie | SIL Open Font License 1.1, volledige tekst in `OFL-Literata.txt` |
| sha256 | `b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440` |
| git blob | `0a81b4984a4a4eb101e0ddc28babc85bb137efef` |
| Assen | `opsz` 7–72 (standaard 12), `wght` 200–900 (standaard 400) |

Het bestand is byte-identiek aan de bron: de git-blob-hash hierboven is dezelfde die de GitHub-API
voor `google/fonts` teruggeeft. Alleen de bestandsnaam is veranderd, van `Literata[opsz,wght].ttf`
naar `Literata-Variable.ttf`, omdat blokhaken in een assetpad door Xcode-buildfases en shellscripts
heen moeten en dat vroeg of laat ergens breekt.

**Controle op de licentie.** De OFL 1.1 laat bundelen in een gesloten of open toepassing toe, zonder
royalty en zonder attributie in de app-UI, mits de licentietekst meegeleverd wordt en het lettertype
niet los verkocht wordt. De copyrightregel van dit bestand is
`Copyright 2017 The Literata Project Authors` **zonder** Reserved Font Name: de enige plek waar die
term in `OFL-Literata.txt` staat is de definitie in de licentie zelf, niet in de kop. Er rust dus
geen hernoemingsplicht op een aangepaste versie, en die maken we hier ook niet. GPL-3.0 en OFL 1.1
botsen niet; het lettertype is data naast het programma, geen afgeleide van de broncode.

**Wat nog moet gebeuren bij de bouw van de reader**, en bewust nog niet gedaan is omdat golden 07
nog geen goedgekeurd contract is:

- een `Literata`-familie in de `fonts:`-sectie van `pubspec.yaml`, met `weight: 400`;
- de licentietekst registreren via `LicenseRegistry.addLicense` in `lib/main.dart`, naast
  `_registerShaderLicenses()`, zodat hij in het scherm Open source-licenties verschijnt. Dat is de
  bestaande conventie van deze repository voor gebundelde derden;
- de `opsz`-as expliciet zetten. Chromium past optical sizing vanzelf toe en neemt de tekengrootte
  in pixels, Flutter doet dat niet en blijft op de standaard 12. Zonder een expliciete
  `FontVariation('opsz', …)` tekent de app een andere snit dan de golden.

**De cursief hoort bij dezelfde familie en zit hier nog niet.** Golden 07 tekent geen cursief, dus
er staat geen ongebruikt bestand van 0,9 MB in de repository. Een EPUB met `<em>` heeft hem wel
nodig, en dan is toevoegen mechanisch: `Literata-Italic[opsz,wght].ttf`, uit dezelfde commit en
onder dezelfde licentie, sha256
`d483dfaeba9cbf4ce71d32a52ee65df82f7e35b15fff8d1011cdb242d1fcd465`, git blob
`8690209cd1bb4d9be1c1a0e976ee2f740c94093b`. Er is dan geen tweede licentieronde nodig.

## Inter en ArchivoBlack

Deze twee stonden er al voordat dit bestand bestond en zijn hier niet opnieuw nagetrokken. Wie ze
aanraakt, legt ze alsnog vast in dezelfde vorm als Literata hierboven.
