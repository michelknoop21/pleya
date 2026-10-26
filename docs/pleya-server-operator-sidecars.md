# Pleya Server: een .nfo voor een map met losse filmpjes

Een bibliotheek van het soort films maakt van elke map één titel, ook als die map honderd losse
bestanden bevat. Op productie is dat Kids: `Efteling Jokie` is één film met 112 versies, `Nijntje`
één film met 6. TMDB kent zo'n map niet, dus de titel blijft `unmatched` en krijgt geen genres. Een
bibliotheek laat genres pas zien als vier van de vijf titels er een hebben (zie
`GenreCoverageThreshold` in `internal/catalog/store_metadata.go`), en Kids staat op 2 van 5.

Een `movie.nfo` in de map lost dat op. `TestMovieNFOInAFolderOfClipsLandsOnTheOneItem` doet het na
met de echte scanner: vijf mappen, de eerste met zes clips, vier met een `movie.nfo`. Elke map blijft
één item, de genres komen uit de `.nfo` (`metadata_sources.genres = nfo`), de dekking is 4 van 5 en
de poort gaat open. Zonder `movie.nfo` in het zoekpad is dezelfde test rood.

## Wat de server leest

Per film zoekt hij `<naam van het bestand>.nfo` naast het bestand en daarna `movie.nfo` in dezelfde
map (`nfo.MoviePath`). Bij een map met veel bestanden pakt hij één bestand als ingang, en dan vindt
`movie.nfo` hem altijd. Staat er naast dat ene bestand ook een geldige `<bestandsnaam>.nfo`, dan gaat die voor.
Het rootelement van een filmbestand moet `<movie>` zijn; een ander element wordt overgeslagen.

Een `.nfo` vult alleen wat de provider niet geeft en wint nergens van een providerwaarde (DEC-153).
Voor een titel die TMDB niet kent is de `.nfo` dus de enige bron.

## Twee bestanden voor Kids

Zet ze naast de clips, dus `Kids/Efteling Jokie/movie.nfo` en `Kids/Nijntje/movie.nfo`. De server
mount de bibliotheek read-only, dus schrijf ze op de NAS zelf, met dezelfde rechten als de clips.
De genres staan in dezelfde Nederlandse woorden als de TMDB-genres die Kids al heeft (Animatie,
Avontuur, Familie), zodat een filter ze samenvoegt. Pas ze aan als je andere woorden wilt.

`Kids/Efteling Jokie/movie.nfo`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>Efteling Jokie</title>
  <plot>Jokie en Jet in de Efteling: muziekclips, korte verhalen en filmpjes waarin Jokie jonge kinderen iets leert.</plot>
  <genre>Familie</genre>
  <genre>Muziek</genre>
</movie>
```

`Kids/Nijntje/movie.nfo`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>Nijntje</title>
  <plot>Afleveringen, muziekclips en compilaties van Nijntje en haar vriendjes.</plot>
  <genre>Animatie</genre>
  <genre>Familie</genre>
</movie>
```

Met deze twee staat Kids op 4 van 5 (Bumba, Pippi Langkous, Efteling Jokie, Nijntje) en dus op 80
procent. `Fien & Teun` blijft zonder genres; één titel zonder is toegestaan.

## Wanneer de server ze leest

Niet meteen. De ronde leest een `.nfo` alleen als de titel aan de beurt is, en `Efteling Jokie`,
`Nijntje` en `Fien & Teun` staan na drie mislukte pogingen op `unmatched` met een volgende poging op
27 oktober 2026 rond 10:18. Daarna duurt het tot 5 minuten voor de poort de nieuwe dekking
meeneemt, want de uitslag wordt zo lang onthouden. Controleer het in scherm 29 (Metadata en
artwork): de genredekking van Kids moet 80 procent tonen. Staat hij daar na de ronde niet, kijk dan
of het bestand `movie.nfo` heet (kleine letters), leesbaar is voor de containergebruiker en met
`<movie>` begint.
