# Tautulli en Aanvragen via iCloud (A-14/A-15/A-21)

Implementatie in voorbereiding op 6 november 2026; tests, onafhankelijke eindreview,
Apple-configuratie en echte cross-device-acceptatie zijn afzonderlijke poorten.

De bestaande iCloud-schakelaar bestuurt ook verbindingssync. Koppelingen gaan via
de private CloudKit-database van het Apple-account, één record
`integration-credentials-v1` van type `PleyaIntegrationCredentialsV1`. Het enige
payloadveld is **Encrypted String** `payloadV1`, geschreven en gelezen met
`CKRecord.encryptedValues`. CloudKit versleutelt dat veld op het apparaat vóór
upload. De lokale vaultsleutel wordt niet gedeeld; de ontvanger versleutelt elke
credential opnieuw voor zijn eigen lokale store. Instellingenexport en KVS
blijven deze geheimen uitsluiten.

## Identiteit, migratie en conflicten

- Tautulli blijft per Plex-server opgeslagen; de bestaande provider controleert
  nog steeds server- en beheerrechten. Legacy-sessies met een bekend server-id
  migreren via de bestaande store. Sessies zonder server-id blijven lokaal tot
  opnieuw koppelen een exact server-id oplevert.
- Aanvragen blijft per profiel. Alleen de bestaande draagbare Plex-profielvorm
  `plex-home-plex.<16 hex account-id>-<16 hex home-id>` synchroniseert. Een leeg
  of lokaal profiel-id wordt niet aan een ander profiel toegewezen; dit volgt
  de identiteitsgrens van DEC-134. Android, Windows en Linux blijven lokaal.
- Een bestaande lokale koppeling krijgt bij de eerste migratie stempel 0; een
  bestaande cloudkeuze wint daarvan. Actuele wijzigingen krijgen een lokale
  tijdstempel met installatie-id als tie-breaker. Een volledige koppeling wint
  als één record; credentials van twee koppelingen worden niet vermengd.
  Tautulli's historiebeleid mergeert apart op `policy_changed_at_ms`; bij een
  gelijke tijd wint uit. Een beleidswijziging verheft geen oude credential of
  verbindingsstaat en maakt een gewiste koppeling niet opnieuw aan.
- Ontkoppelen schrijft een permanente tombstone. Een CAS-conflict herleest de
  cloud vóór een nieuwe poging. Een mislukte lezing geldt nooit als een lege
  store. Een importjournal met uitsluitend lokaal versleutelde bytes bewaart
  de oorspronkelijke revisie over een crash heen.
- De eerste geslaagde sync bindt de lokale outbox aan dat Apple-account. Een
  ander iCloud-account blokkeert verdere overdracht; de interface vraagt om
  opnieuw aanmelden bij het oorspronkelijke account. Lokale koppelingen blijven
  beschikbaar. Er is geen automatische overdracht naar een nieuw Apple-account.
- Lokale wijzigingen en foreground starten een pass; een voorgrondpoll herleest
  elke minuut. Remote wijzigingen laten de bestaande providers herladen.

## Apple-releasepoort

De runners vragen CloudKit aan voor `iCloud.$(CFBundleIdentifier)`; Verify heeft
daardoor zijn eigen container en krijgt geen toegang tot productiecredentials.
Fixture-runs (`PLEYA_VERIFY`) starten deze credentialservice niet en vragen geen
echt Apple-account op; de regressietests gebruiken een fake transport.
Vóór een ondertekende bundelbuild moet de bevoegde releasehouder:

1. De container `iCloud.nl.michelknoop.pleya` aan de productie-appidentiteiten
   koppelen en passende iOS/iPadOS-, tvOS- en macOS-profielen laten maken.
2. In de ontwikkelschemaomgeving het recordtype en het **Encrypted String**-veld
   aanmaken/verifiëren en het schema naar Production deployen. Een gewoon String-
   veld is geen vervanging en wordt niet als fallback gelezen of geschreven.
3. Verify afzonderlijk provisionen onder zijn eigen bundle/container-identiteit.
4. Op twee eigen toestellen migratie, wijzigen, offline ontkoppelen, herstart,
   iCloud uit/aan en accountwissel bewijzen met de gezamenlijke geaccepteerde build.

Deze Apple-configuratie en de vereiste ASC-grants zijn niet in de code aanwezig
en zijn in deze taak niet gebruikt. Er is geen gedeeltelijke release gestart.
