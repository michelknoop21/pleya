# Lokale ontdekking: begrensd protocolvenster

Roadmap: C-06 / S26.9. Michel gaf op 13 november 2026 akkoord op dit venster: alleen de UDP-oproep en het antwoord waarmee een client een Pleya Server op het thuisnetwerk vindt. `openapi.yaml` verandert niet; de uitwisseling staat buiten HTTP en is beschreven in [hoofdstuk 5.1 van het protocol](pleya-protocol-v1.md#51-vinden-op-het-thuisnetwerk). Besluit: DEC-XXX (lokale ontdekking) in [DECISIONS](DECISIONS.md).

## Wat erbij komt

- Een client stuurt een UDP-broadcast naar poort 48635 met de tekst `who is PleyaServer?`.
- Een server die ontdekking aan heeft staan, antwoordt rechtstreeks aan de afzender met één JSON-object: `app`, `v`, `id`, `name`, `port` en `scheme`.
- De client bouwt het adres uit het afzenderadres van het antwoord plus `scheme` en `port`. Geen veld in het antwoord kan een andere host aanwijzen; `url` is gereserveerd voor de TLS-stap en wordt genegeerd.

Dit is additief binnen protocolmajor 1. Geen bestaand veld, pad of gedrag verandert. Een server zonder ontdekking antwoordt niet en een client zonder ontdekking vraagt niets; beide werken zoals voorheen met een ingetypt adres.

## Wat er niet bij komt

- Geen toegang, geen token en geen gebruikersgegevens in het antwoord. Inloggen blijft nodig.
- Geen vertrouwen. Iedereen op het netwerk kan zich als server voordoen. De client vergelijkt daarom de `id` uit het antwoord met `server.id` uit `GET /info` op het gevonden adres en gaat bij een verschil niet door naar het inlogscherm; het gevonden adres wordt dan uit het veld gehaald. Dat vangt een verwisseling of een oud antwoord, geen aanvaller die ook `/info` nabootst; daar is de TLS-stap van S26 voor.
- Geen ontdekking buitenshuis. Daar blijft de uitnodiging de weg (S26.3 en S26.4).
- Geen mDNS. De app heeft al twee UDP-bakens en een Jellyfin-ontdekking op hetzelfde patroon; een tweede mechanisme voegt niets toe.

## Standaard uit

`PLEYA_SERVER_DISCOVERY_ADDR` staat standaard op `off`. De server is standaard alleen op loopback gepubliceerd en heeft dan niets te melden. De beheerder zet ontdekking aan met `PLEYA_SERVER_LAN=on` in `.env`; `deploy-nas.sh` voegt dan `compose.lan.yaml` toe. Zie de [operatorhandleiding](pleya-server-operator-remote.md#vindbaar-op-het-thuisnetwerk).

## Sluitcriteria

1. Servertests met een echte UDP-socket: antwoord op de exacte oproep, stilte op al het andere, limiet per afzender, antwoord van hoogstens 512 bytes, begrensd register van afzenders.
2. Clienttests: parsen, adres uit de afzender, een `url` verandert het adres niet, vreemde `app` of `v` overgeslagen, afwijkende `id` geeft geen inlogstap.
3. De echte Go-luisteraar en de Dart-dienst vinden elkaar in één proef.
4. Onafhankelijke review.
5. Op de NAS: een broadcast bereikt de container via de gepubliceerde UDP-poort. Lukt dat niet in een bridge-netwerk, dan draait dezelfde luisteraar met `network_mode: host`. Controleer daarbij ook of de container het echte afzenderadres ziet: herschrijft Docker het, dan delen alle toestellen één limiet van vijf antwoorden per tien seconden.
6. Op een iPhone en een Apple TV: de broadcast vertrekt en het antwoord komt aan.

Punt 5 en 6 kunnen niet in een cloudsessie. Het venster sluit pas als ze gedaan zijn; een groene deeltest sluit het niet. NAS-deploy en release krijgen door dit venster geen vrijgave.
