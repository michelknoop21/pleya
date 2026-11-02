# C-05 / S13.4 — ondertitels in de browserspeler

Lokale clientaansluiting op bestaande routes, na `05534767`; pakket 5 blijft open. Geen nieuw protocol, extra downloadservice of afhankelijkheid.

SRT-sidecars worden in de bestaande trackketen omgezet naar WebVTT. Ingebedde SRT/VTT verschijnt alleen achter `embedded_subtitles` en gebruikt dezelfde geautoriseerde ondertitelroute. De omzetter bewaart cue-identiteiten, Unicode en regels, verwerkt BOM/CRLF en weigert ongeldige tijden, onbekende formaten en meer dan 4 MiB tekst. ASS/bitmap wordt hiermee niet als browsertekst ondersteund; de webconsumptie van het bestaande burn-pad blijft onder S18 open.

Een nieuwe keuze vervangt de actieve ondertitel pas na succesvol laden en omzetten. Laden is zichtbaar; een fout meldt dat de vorige keuze actief blijft. Uit, sluiten en een nieuwe keuze annuleren de oude aanvraag; late blob-URLs worden vrijgegeven. Escape werkt ook vanaf een keuzerondje en zet de focus terug op de opener.

**Bewijs.** 8 bestanden / 98 gerichte spelertests PASS; bredere auth/speler/Home-regressie 13 bestanden / 184 PASS. Sveltecheck 0 fouten en 0 waarschuwingen, productie-webbundel groen. Tests eerst rood voor SRT en publieke callers; afzonderlijke negatieve controles rood bij het verwijderen van behoud van de actieve ondertitel, budget en late-annuleringscontrole. Keyboardtest eerst rood op Escape en daarna rood op ontbrekend focusherstel; beide groen na reparatie.

Echte eigen Go-server en synthetische video: Chromium decodeert 79 frames, tekent de sidecar en het ingebedde spoor, behoudt de vorige ondertitel bij een nagebootste 503 en schakelt echt uit. Op 1920/1440/1280/390/320: axe 0 en horizontale overloop 0; beelden bekeken. Escape/focusherstel ook in de browser groen. Bewijs: `.build/pleya-completion-evidence/web-subtitles/proof.json` en [beeldenmanifest](2026-10-29-pleya-completion-images.md).

**Open.** Onafhankelijke branchreview, overige formaten/burnconsumptie en platform-/NAS-acceptatie. Dit is geen fysieke toestel-, productie- of releaseacceptatie.
