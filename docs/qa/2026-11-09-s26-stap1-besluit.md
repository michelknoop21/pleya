# S26 Delen, stap 1: inventarisatie en besluit (docs-only)

9 november 2026. Roadmap C-06 / S26.1. Branch `claude/happy-brown-l9so1b`, basis `main` op `655a001`. Geen code, geen protocolvenster, geen deploy.

## Commits

- `aca3aa7` docs(server): S26 Pleya Server delen via uitnodigingen, besluit en plan. Voorstel (`docs/pleya-server-sharing-proposal.md`), plan (`docs/plans/2026-11-09-pleya-server-delen/PLAN.md`), DEC-XXX (Pleya Server delen) en statusnoot bij DEC-037, roadmaprij en sectie C-06, masterlijstslice S26 met acht taken, noot bij architectuur 15.
- Herstelcommit na review (zie hieronder): twee verouderde regelverwijzingen in het plan, de hercontroledatum in de masterlijst, een verduidelijking bij DEC-117/DEC-120 (nummers komen dubbel voor), een hernummerchecklist voor DEC-XXX in het voorstel (hoofdstuk 9) en de WIP-consequentie in de roadmapsectie C-06.

## Bewijs

- `scripts/masterlist_counts.sh --check`: "masterlijst klopt: 172 taken, 92 gereed, 39 bezig, 41 open", exit 0, voor en na de herstelcommit.
- Links en anchors van de nieuwe tekst gecontroleerd met een script over relatieve paden en kopjes; `#c-06-pleya-server-delen`, `#s26-delen-ps-17`, de DEC-037- en DEC-XXX-anchors lossen op.
- `git show HEAD | grep '^+' | grep '—'` leeg: geen em-dash in de toegevoegde regels.
- Onafhankelijke docs-review vanuit een aparte seat: geen Critical. Important 1 (anchors breken bij hernummering van DEC-XXX) is verwerkt als merge-checklist in het voorstel. Minor 2, 3, 4, 6 en 8 zijn hersteld. Minor 5 (statusvorm "accepted; gedeeltelijk vervangen" in plaats van `superseded`) is bewust zo gelaten: DEC-037 blijft deels gelden, precedent DEC-005. Minor 7 afgewezen met reden: de zinnen over e-mail via bestaande mailfunctionaliteit en over het weglaten van domein-, proxy- en VPN-keuzes uit de uitnodigingsflow komen letterlijk uit Michels opdracht van 9 november, en het plan is door Michel goedgekeurd in de plansessie van dezelfde dag; de repo kan dat laatste alleen via dit rapport en DEC-XXX vastleggen.
- De reviewer verifieerde de technische claims uit het voorstel (hoofdstuk 7) en het plan tegen de repo: `ListenAndServe` zonder TLS, loopbackpoort in `compose.yaml`, afgeleide companionsleutel, `http://`-default in `normaliseBaseUrl`, één `baseUrl` per Pleya Server-verbinding, geen `badCertificateCallback`, relaylimieten in `server/main.go`, statische website met downloadteller, geen uitgaande aanroep naar pleya.app vanuit de server.

## Open

- Bevestiging in stap 1 van wat de Go-relaystack achter `ice.pleya.app` kan dragen voor de centrale dienst, en het vertrouwensmodel per sleutel (NAS, toestel, centrale dienst).
- Nummer voor DEC-XXX bij de merge, met de checklist uit hoofdstuk 9 van het voorstel.
- Vanaf stap 2 telt S26 mee in de WIP-limiet naast de C-05-uitvoering; afweging bij de start van stap 2.
