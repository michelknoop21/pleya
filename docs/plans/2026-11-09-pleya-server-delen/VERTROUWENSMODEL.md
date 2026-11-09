# Vertrouwensmodel S26: wie bewijst wat, met welke sleutel

**Roadmap:** C-06 / S26.1. **Besluit:** DEC-XXX (Pleya Server delen), besluit 5 tot en met 12. **Bewijs:** de cloudproef in [`tool/s26_proof`](../../../tool/s26_proof/README.md) en het [rapport](../../qa/2026-11-09-s26-stap2-cloudproef.md). Dit document is de ontwerpbasis voor stap 3 tot en met 6. Het opent geen protocolvenster.

## Uitgangspunten

1. **De NAS dwingt toegang af.** Bij elk verzoek beslist de server wat iemand mag. De centrale dienst coördineert, maar is wel een vertrouwde partij: zie het volgende kopje.
2. **Geen privésleutel verlaat de plek waar hij gemaakt is.** Sleutels van de NAS blijven op de NAS, sleutels van een toestel op dat toestel.
3. **TLS eindigt op de NAS,** ook via de relay. De relay en het netwerk kunnen de media niet lezen.
4. **Twee barrières tegen verwisselen van servers:** de naam is afgeleid van de serveridentiteit, en het certificaat hoort bij die naam. Valt de eerste weg, dan houdt de tweede het tegen (proef: `TestServerCannotClaimAnotherServersName` en `TestFRPWithoutPluginGivesTheRouteToTheFirstClaimant`).

## De centrale dienst is vertrouwd voor uitgifte en identiteit

In de accountmodus kan de centrale dienst meer dan coördineren:

- Met het ACME-account en de DNS-API-sleutel kan hij een geldig certificaat laten uitgeven voor elke `*.H.<serverdomein>`, met een sleutel naar keuze. De naamcontrole in de uitgifte is zijn eigen code en bindt dus alleen een eerlijke beheerder.
- Hij levert de app de routes van een server.
- Hij vertelt de server welk account een uitnodiging accepteerde.

Wie de centrale dienst, de DNS-API-sleutel of het ACME-account in handen krijgt, kan daarom een server nabootsen, de routes van een slachtoffer naar zichzelf laten wijzen, en elke speler accepteert het publiek vertrouwde certificaat. Dat is een volledige man-in-the-middle op media en tokens. Hij kan ook openstaande uitnodigingen inwisselen of zich voordoen als een account dat al toegang heeft. Certificate Transparency laat zo'n certificaat pas achteraf zien.

**Dit is dezelfde vertrouwensrelatie als bij Plex.** Wie dat niet wil, gebruikt de zelfstandige modus. Om de schade te beperken, krijgt stap 3:

1. **CAA op het serverdomein** met `accounturi` en `validationmethods=dns-01`, zodat alleen het ACME-account van de centrale dienst kan laten uitgeven, en alleen via DNS-01. Dit helpt tegen misbruik van de DNS-sleutel alleen, niet tegen overname van de hele dienst.
2. **De app pint de serveridentiteit na het eerste contact.** Bij elke verbinding laat de app de server een uitdaging tekenen met de identiteitssleutel, gebonden aan de TLS-sessie (TLS exporter). Een later vervalst certificaat met een andere identiteit valt dan op, ook al is het publiek geldig. Het eerste contact blijft afhankelijk van de centrale dienst.
3. **De server bewaakt CT** voor zijn eigen `*.H` en meldt de eigenaar elk certificaat dat hij niet zelf aanvroeg.
4. **De server meldt nieuwe toestellen** en kan per account eisen dat de eigenaar een nieuw toestel of een geaccepteerde uitnodiging bevestigt.
5. **De DNS-API-sleutel en het ACME-account zijn de waardevolste geheimen** van het systeem. Ze komen niet op dezelfde plek als de webinterface, krijgen minimale rechten (alleen TXT-records onder `_acme-challenge`) en worden geroteerd bij de verhuizing naar de VPS.

## Sleutels en geheimen

| Sleutel | Waar | Gemaakt door | Bewijst | Rotatie en herstel |
| --- | --- | --- | --- | --- |
| **Serveridentiteit** (Ed25519) | NAS, naast `token-signing.key` | De server, bij de eerste koppeling | "Ik ben de server met hash H", met H = base32(SHA-256(publiek)[0:16]) | Roteert niet mee met `token-signing.key`. De companionsleutel in `internal/auth/companion.go` roteert wel mee en is daarom ongeschikt. Hoort in de S25-back-up, maar alleen als `PLEYA_SERVER_BACKUP_KEY` is gezet, want zonder die sleutel laat de back-up geheimen weg. Na verlies: een nieuwe identiteit met een nieuwe hash, en de eigenaar koppelt opnieuw. |
| **TLS-sleutel** (ECDSA P-256) | NAS | De server, bij elke aanvraag of verlenging | Het certificaat `*.H.<serverdomein>` hoort bij deze server | Mag bij elke verlenging nieuw zijn (proef: `TestRenewalWithSameAndRotatedKey`). Hoeft niet in de back-up. |
| **ACME-account** | Centrale dienst | De centrale dienst | Tegenover de CA: dat deze dienst mag aanvragen | Samen met de DNS-sleutel het waardevolste geheim, zie hierboven. Gebonden via CAA `accounturi`. |
| **DNS-API-sleutel** | Centrale dienst | De beheerder van het serverdomein | Dat de dienst DNS-01 kan uitvoeren | Minimale rechten. Op de NAS zolang de dienst daar draait; nieuw bij de verhuizing. |
| **Pleya-accountsessie** | Toestel en centrale dienst | De centrale dienst bij aanmelden | Wie de persoon is | Kort access-token en een roterende refresh, naar het patroon van de refresh-rotatie in DEC-117. Intrekbaar per toestel. |
| **Servertoegang** | Pleya Server | De server bij acceptatie van een uitnodiging | Welke bibliotheken en rechten een account op deze server heeft | Bestaande rollen en rechtenladder (DEC-119), sessies per toestel (DEC-123), het intrekregister uit DEC-120 (het besluit over intrekken binnen twee seconden). |
| **Relayregistratie** | NAS naar relay | De NAS | "Deze verbinding is van server H, voor deze relay" | frp: een handtekening in de metadata die de plugin bij Login en NewProxy controleert. Eigen relay: een ondertekend bericht met relay-id, tijdstempel en nonce. |

## Wat elke partij weet

| Partij | Weet | Weet niet |
| --- | --- | --- |
| Centrale dienst | Accounts, welke servers aan welk account hangen, publieke serveridentiteiten, uitnodigingen en wie ze accepteerde, de routes van een server (ook het IP-adres thuis), relaygebruik per server | Media, bibliotheekinhoud, kijkgedrag, TLS-sleutels, wachtwoorden van servergebruikers. Hij kan wel onderscheppen als hij gecompromitteerd is, zie hierboven. |
| Relay | Welke server-hash hoeveel bytes doorgeeft, IP-adressen, tijdstippen | De inhoud: alleen cijfertekst (proef: `TestRelayForwardsOnlyCiphertext`, met een detector die klare tekst wel ziet) |
| DNS-provider, CA en iedereen die CT-logs leest | Dat er een server met hash H bestaat | Eigenaar en locatie, zolang er geen publieke DNS-records met IP-adressen onder `H` staan |
| Pleya Server | Alles over zijn eigen gebruikers en media, zoals nu | Andere servers |

**Geen publieke DNS-records met IP-adressen.** Elke hash staat in de openbare CT-logs. Stond `direct.H` met het thuisadres in publieke DNS, dan kan iedereen een lijst van thuis-IP's met een mediaserver maken. Daarom levert de centrale dienst het directe en het lokale adres alleen in de routegegevens aan een aangemeld account. De app verbindt via de CONNECT-proxy op het toestel, zoals bij de lokale route (proef: `TestLocalRouteSurvivesRebindingProtection`). Alleen de relaynamen (`r1.H`) staan in publieke DNS, en die wijzen naar de relay, niet naar een huis.

**De browser kan de proxy op het toestel niet gebruiken.** Pleya Web in Safari of Chrome heeft alleen DNS. Voor de browser blijven daarom twee routes over: de relay, en de lokale naam als een DNS-dienst namen als `192-168-1-10.H` uit het label zelf beantwoordt, zoals plex.direct. Zo'n antwoord bevat alleen een privé-adres dat al in de naam staat, en verraadt dus geen thuisadres. Het loopt wel tegen DNS-rebindingbescherming in routers aan, en valt dan terug op de relay. De directe route met het publieke thuisadres is voor de browser niet beschikbaar. Een kijker in de browser thuis gaat dus via de lokale naam of via de relay; buitenshuis altijd via de relay. Dat kost relaybandbreedte, en het toesteldraaiboek moet het meten.

## De drie stromen

**1. Server koppelen en certificaat krijgen** (stap 3, bewezen in `certflow`)
1. De eigenaar meldt zich in de wizard aan bij zijn Pleya-account. De centrale dienst geeft een eenmalige uitdaging.
2. De server tekent uitdaging plus account-id met zijn identiteitssleutel. Wie alleen de publieke sleutel kent, kan niet registreren. Een handtekening werkt niet voor een ander account. Een server hoort bij één account (proef: `TestRegistrationNeedsPossessionAndOneOwner`). Overdracht naar een ander account is nog niet ontworpen of gebouwd; het voorstel is dat ook die een nieuwe handtekening van de identiteit vraagt.
3. De server stuurt een CSR voor precies `*.H.<serverdomein>`, ondertekend met de identiteitssleutel. De centrale dienst weigert een andere naam, een andere handtekening en een niet-geregistreerde identiteit (`TestIssueRefusesWhatIsNotTheCallersName`).
4. De centrale dienst doet DNS-01 en geeft de keten terug. De TLS-sleutel blijft op de NAS (`TestIssueKeepsKeyOnNASAndCoversRouteNames`).

**2. Uitnodiging accepteren** (stap 4, ontwerp)
1. De beheerder maakt op de server een uitnodiging met bibliotheken en rechten. De server meldt hem aan bij de centrale dienst met een eenmalige code.
2. De link wijst naar pleya.app en bevat die code. **Wie de link heeft, kan hem met elk account inwisselen.** De code is dus een tijdelijke toegangsbelofte. Een uitgelekte link wordt beperkt door een korte geldigheid, eenmalig gebruik, en een keuze per uitnodiging: binden aan het e-mailadres van de ontvanger, of acceptatie laten bevestigen door de eigenaar.
3. De ontvanger meldt zich aan of maakt een account aan. De centrale dienst meldt de server welk account accepteerde.
4. De server maakt of koppelt een servergebruiker met precies de rechten uit de uitnodiging, en geeft pas daarna sessies uit aan toestellen van dat account.
5. De app krijgt van de centrale dienst de hash, de publieke identiteit en de routes. Vanaf het eerste contact pint de app de identiteit.

**3. Verbinden en kijken** (stap 5 en 6, bewezen in `relay`, `frpeval` en `players`)
1. De app kiest uit de routes: lokaal (`a-b-c-d.H`), rechtstreeks, relay (`r1.H`). Alle namen vallen onder hetzelfde wildcardcertificaat. Een naam twee labels diep valt er niet onder, daarom gebruikt de lokale route streepjes in plaats van punten.
2. **Elke speler moet het certificaat én de hostnaam controleren.** ffmpeg en mpv doen standaard geen van beide. Met `tls-verify` aan weigeren ze een vals certificaat en ook een geldig certificaat van een andere server (proef: `players`). De app zet dit expliciet aan voor mpv en elke ffmpeg-route. Op MPVKit moet het toesteldraaiboek bevestigen dat de hostnaam echt gecontroleerd wordt.
3. **Geen bearer-header naar de speler waar een redirect naar een andere host kan volgen.** ffmpeg en mpv sturen `Authorization` mee naar de nieuwe host; `dart:io` en de Go-client niet (`TestAuthorizationHeaderOnCrossHostRedirect`). Voor de speler gebruikt S26 een kortlevend, versiegebonden streamtoken, of een proxy op het toestel die de header alleen naar de geverifieerde host stuurt. CupertinoClient en Cronet staan in het toesteldraaiboek.
4. **De lokale en directe route hangen niet aan DNS.** De app gebruikt de adressen uit de routegegevens via de CONNECT-proxy op het toestel; de speler houdt de hostnaam voor TLS. Zo breekt DNS-rebindingbescherming in routers de lokale route niet, en staat het thuisadres niet in publieke DNS.

## Dreigingen en antwoord

| Dreiging | Antwoord | Bewijs |
| --- | --- | --- |
| Centrale dienst, DNS-sleutel of ACME-account gecompromitteerd | Zie hierboven: CAA, identiteitspinning in de app na het eerste contact, CT-bewaking door de server, bevestiging van nieuwe toestellen, minimale rechten; de zelfstandige modus voor wie dit risico niet wil | Ontwerp; de pinning en CT-bewaking worden bewezen in stap 3 en 5 |
| Iemand registreert de server van een ander onder zijn account | Uitdaging plus account-id, getekend met de identiteitssleutel; één account per server | `TestRegistrationNeedsPossessionAndOneOwner` |
| Iemand vraagt een certificaat aan voor de naam van een ander | De naam moet afgeleid zijn van de ondertekenende, geregistreerde identiteit | `certflow`, met negatieve controle |
| Een server neemt bij de relay de naam van een ander over | Hash afgeleid van de sleutel, handtekening, autorisatie; frp via een plugin bij Login en NewProxy, alleen type `https`; daarachter het certificaat | `relay` en `frpeval`, met negatieve controle zonder plugin |
| Replay van een relayregistratie | Eigen relay: nonce, tijdstempel en relay-id. Het control-kanaal in de proef is gewone TCP en de sessie is niet aan de registratie gebonden, dus iemand op het pad kan de sessie overnemen (dienstweigering; TLS blijft staan). In productie loopt het control-kanaal over TLS. frp: de handtekening in de metadata is statisch en daarmee een geheim op de NAS, zoals een API-sleutel; het control-kanaal moet over TLS | `relay` met negatieve controle; TLS-control-kanaal open |
| Relay of netwerk leest mee | TLS eindigt op de NAS | `relay` met detectorcontrole; `frpeval` ziet het NAS-certificaat |
| Man-in-the-middle of een ander serverscertificaat op een route | Verificatie van keten en hostnaam in elke speler, geen stille terugval naar HTTP | `players`: geweigerd met verificatie, geaccepteerd zonder |
| Token lekt via een redirect | Geen bearer-header naar spelers bij een mogelijke redirect; versiegebonden token | `players` |
| Thuisadressen uit CT-logs plus publieke DNS | Geen publieke DNS-records met IP-adressen onder `H` | Ontwerp |
| Uitgelekte uitnodigingslink | Kort geldig, eenmalig, optioneel gebonden aan de ontvanger of bevestigd door de eigenaar | Ontwerp, stap 4 |
| Uitval van de centrale dienst | Bestaande sessies op de server werken door tot hun refresh verloopt; nieuwe accounts en uitnodigingen wachten | Ontwerp, besluit 10; te bewijzen in stap 8 |
| Uitval thuis in de NAS-fase | Aanmelden en relay vallen weg voor alle gebruikers; directe en lokale routes van andere servers werken door met gecachte routes | Ontwerp; reden voor de verhuizing naar de VPS |

## Hosting in fases

Besluit 12 legt vast: eerst de NAS, later een VPS. De invulling hieronder is een voorstel, geen besluit van Michel.

- **NAS-fase:** de centrale dienst draait als eigen container met eigen database achter de bestaande Cloudflare Tunnel. Daar gaat alleen coördinatieverkeer over, maar Cloudflare kan dat verkeer lezen, en dus ook accountsessies. De relay kan niet achter de tunnel, want die termineert TLS. De relay krijgt een eigen inkomende poort; die poort op de router doorzetten is een actie die Michel zelf moet goedkeuren.
- **VPS-fase:** dezelfde containers met dezelfde DNS-namen op een VPS. De verhuizing is een DNS- en deploywijziging. De DNS-API-sleutel en het ACME-account worden dan vervangen.

## Open voor stap 3 en later

- Identiteitspinning in de app met een handtekening gebonden aan de TLS-sessie, op alle spelerstacks (de spelers zelf kennen dit niet, dus het hoort bij de app-laag vóór het afspelen).
- frp-control-kanaal over TLS, en frpc als losse container of als bibliotheek.
- De precieze termijn voor het intrekken van bestaande sessies, en het cachen van routes bij uitval.
- Spelergedrag op echte toestellen, inclusief de hostnaamcontrole van MPVKit en de redirectregels van CupertinoClient en Cronet: zie het [toesteldraaiboek](PROEF-TOESTELLEN.md).
