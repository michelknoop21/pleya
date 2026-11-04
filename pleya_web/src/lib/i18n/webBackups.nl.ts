/** De Nederlandse helft van `webBackups.ts` (S25.6). Termen volgen de northstar, je-vorm, kort. */
import type { webBackups } from './webBackups';

export const webBackupsNl = {
  'admin.bak.title': 'Onderhoud',
  'admin.bak.link': 'Onderhoud en back-ups',
  'admin.bak.create': 'Nu een back-up maken',
  'admin.bak.creating': 'Bezig met starten…',
  'admin.bak.notice.created': 'De back-up staat in de wachtrij. Deze pagina volgt hem tot hij klaar is.',
  'admin.bak.notice.verifying': 'De hersteltest staat in de wachtrij. Deze pagina volgt hem tot hij klaar is.',
  'admin.bak.unsupported.title': 'Deze server maakt geen back-ups',
  'admin.bak.unsupported.body':
    'De server biedt geen back-ups aan (capabilities.backups staat uit). Werk de server bij naar een versie die dat wel doet.',

  'admin.bak.list.title': 'Back-ups',
  'admin.bak.list.summary': '{dir} · dagelijks om {time} · {days} bewaard',
  'admin.bak.days.one': '{count} dag',
  'admin.bak.days.other': '{count} dagen',
  'admin.bak.titles.one': '{count} titel',
  'admin.bak.titles.other': '{count} titels',
  'admin.bak.empty': 'Er zijn nog geen back-ups. De eerste komt om {time}, of druk op Nu een back-up maken.',
  'admin.bak.col.made': 'Gemaakt',
  'admin.bak.col.content': 'Inhoud',
  'admin.bak.col.size': 'Grootte',
  'admin.bak.col.status': 'Status',
  'admin.bak.col.test': 'Hersteltest',
  'admin.bak.col.actions': 'Acties',
  'admin.bak.size.unknown': 'onbekend',
  'admin.bak.explain':
    'Een back-up bevat de database en de bestanden uit /config. De ondertekensleutel zit er alleen versleuteld in, en alleen als er een sleutel is ingesteld. Mediabestanden zitten er nooit in. De hersteltest zet de back-up terug in een aparte, tijdelijke database en telt titels, gebruikers, bibliotheken en kijkstatus na; de echte database blijft onaangeraakt.',

  'admin.bak.status.ok': 'ok',
  'admin.bak.status.running': 'bezig',
  'admin.bak.status.failed': 'mislukt',
  'admin.bak.status.missing': 'bestand weg',
  'admin.bak.trigger.schedule': 'dagelijks',
  'admin.bak.trigger.manual': 'handmatig',
  'admin.bak.trigger.upgrade': 'vóór een upgrade',
  'admin.bak.content.database': 'database en /config',
  'admin.bak.content.schema': 'database (schema {schema}) en /config',
  'admin.bak.secrets.in': 'geheimen erin, versleuteld',
  'admin.bak.secrets.out': 'zonder geheimen',
  'admin.bak.test.never': 'niet getest',
  'admin.bak.test.running': 'wordt getest',
  'admin.bak.test.ok': 'hersteltest geslaagd',
  'admin.bak.test.failed': 'hersteltest mislukt',
  'admin.bak.test.counted': '{found} van {expected} titels',
  'admin.bak.failure.storageFull': 'de schijf was vol',
  'admin.bak.failure.database': 'de database was niet bereikbaar',
  'admin.bak.failure.code': 'de server meldde {code}',
  'admin.bak.failure.unknown': 'de server noemde geen reden',

  'admin.bak.action.verify': 'Hersteltest',
  'admin.bak.action.verifyFor': 'Hersteltest draaien op de back-up van {when}',
  'admin.bak.action.restore': 'Terugzetten',
  'admin.bak.action.restoreFor': 'De back-up van {when} terugzetten',
  'admin.bak.action.busy': 'Er loopt een back-up of hersteltest. Wacht tot die klaar is.',

  'admin.bak.settings.title': 'Instellingen',
  'admin.bak.settings.help':
    'Deze komen uit de omgeving van de server en zijn hier niet te wijzigen: een bewaartermijn die via het web omlaag kan, kan ook omlaag door iemand die een beheerdersaccount heeft overgenomen. Pas ze aan in het compose-bestand of op de NAS en herstart de server.',
  'admin.bak.settings.dir': 'Map',
  'admin.bak.settings.time': 'Tijdstip',
  'admin.bak.settings.timeValue': 'elke dag om {time}',
  'admin.bak.settings.retention': 'Bewaartermijn',
  'admin.bak.settings.retentionNote': 'De nieuwste geslaagde back-up blijft altijd staan.',
  'admin.bak.settings.key': 'Sleutel voor de geheimen',
  'admin.bak.settings.keySet': 'ingesteld',
  'admin.bak.settings.keyNotSet': 'niet ingesteld',

  'admin.bak.warn.failed.title': 'De laatste back-up is mislukt',
  'admin.bak.warn.failed.body':
    'Reden: {reason}. De oudere back-ups staan er nog. Los de oorzaak op en druk op Nu een back-up maken.',
  'admin.bak.warn.domain.title': 'De back-upmap staat op dezelfde schijf als de configuratie',
  'admin.bak.warn.domain.body':
    '{dir} staat op hetzelfde bestandssysteem als /config. Een back-up daar beschermt tegen een mislukte upgrade of een verkeerde handeling, maar niet tegen een kapotte schijf. Zet de map op een andere schijf of een NAS-share.',
  'admin.bak.warn.noKey.title': 'Geen sleutel ingesteld voor de geheimen',
  'admin.bak.warn.noKey.body':
    'Zonder {variable} blijven de geheimen uit /config buiten een back-up. Na een restore op een lege server moet iedereen opnieuw inloggen. Stel een wachtzin in van minstens zestien tekens en bewaar die buiten de NAS.',
  'admin.bak.warn.testNever.title': 'Er is nog geen back-up getest',
  'admin.bak.warn.testNever.body':
    'Een back-up is pas een back-up als hij teruggezet is. Druk op Hersteltest bij de nieuwste back-up; de server doet dit ook wekelijks zelf.',
  'admin.bak.warn.testOld.title': 'De laatste hersteltest is te oud',
  'admin.bak.warn.testOld.body':
    'De laatste geslaagde hersteltest is ouder dan {days} dagen. De server draait er wekelijks een na de geplande back-up, dus er kan iets vastzitten. Druk op Hersteltest bij de nieuwste back-up.',
  'admin.bak.warn.missing.title': 'Een back-upbestand ontbreekt',
  'admin.bak.warn.missing.body.one':
    '{count} back-up is uit {dir} verdwenen zonder dat de server hem weghaalde. Is de map verplaatst of opgeruimd?',
  'admin.bak.warn.missing.body.other':
    '{count} back-ups zijn uit {dir} verdwenen zonder dat de server ze weghaalde. Is de map verplaatst of opgeruimd?',

  'admin.bak.restore.title': 'Terugzetten',
  'admin.bak.restore.body':
    'Zet de server in onderhoudsmodus, laadt de database en /config uit de gekozen back-up en start opnieuw. Kijkstatus, gebruikers, sessies, instellingen en scans van na die back-up gaan verloren. Daarom staat Terugzetten alleen bij een back-up die geslaagd is.',
  'admin.bak.restore.older':
    'Een back-up van een nieuwer schema dan deze server is niet terug te zetten; de server weigert hem en zegt waarom.',
  'admin.bak.restore.confirmTitle': 'De back-up van {when} terugzetten?',
  'admin.bak.restore.confirmBody':
    'Dit vervangt de huidige gegevens en is niet ongedaan te maken. Maak eerst een nieuwe back-up als je wilt bewaren wat er nu staat.',
  'admin.bak.restore.lose': 'Wat er gebeurt, in deze volgorde:',
  'admin.bak.restore.step1':
    'De server controleert de back-up. Klopt er iets niet, dan stopt hij hier en verandert er niets.',
  'admin.bak.restore.step2':
    'De server gaat in onderhoudsmodus: elke aanvraag wordt geweigerd en streams stoppen.',
  'admin.bak.restore.step3':
    'De database en /config worden vervangen door de back-up. Alles van daarna gaat verloren: kijkstatus, gebruikers, sessies, instellingen en scans.',
  'admin.bak.restore.step4':
    'De server start zelf opnieuw. Jij en andere ingelogde gebruikers moeten mogelijk opnieuw inloggen.',
  'admin.bak.restore.sentence': 'Typ deze zin precies over om te bevestigen:',
  'admin.bak.restore.phrase': 'Bevestigingszin',
  'admin.bak.restore.confirm': 'Deze back-up terugzetten',

  'admin.bak.wait.title': 'De server zet de back-up terug',
  'admin.bak.wait.body':
    'Dit duurt enkele minuten en de server is ondertussen niet bereikbaar. Deze pagina kijkt om de paar seconden of hij weer antwoordt. Je mag het tabblad sluiten, de server gaat door.',
  'admin.bak.back.title': 'De server antwoordt weer',
  'admin.bak.back.body':
    'Het terugzetten is klaar, of het is mislukt en de server draait op de database van daarvoor (hij herstart in beide gevallen). Kijk in de lijst en in het serverlogboek bij Diagnostiek welk van de twee het was.',
  'admin.bak.back.list': 'Naar de lijst',
  'admin.bak.back.log': 'Serverlogboek',
  'admin.bak.signin.title': 'Log opnieuw in',
  'admin.bak.signin.body':
    'De server is terug, maar jouw sessie staat niet in de teruggezette database. Log opnieuw in om het resultaat te zien.',
  'admin.bak.signin.action': 'Inloggen',
  'admin.bak.timeout.title': 'De server antwoordt nog niet',
  'admin.bak.timeout.body':
    'Na tien minuten komt er nog geen antwoord. De server herstart via het herstartbeleid van zijn container; staat die stil, start hem dan op de NAS en lees zijn log. Begin geen tweede restore.',
  'admin.bak.timeout.action': 'Opnieuw controleren',

  'admin.bak.err.busy':
    'Er wacht of loopt al een back-up of hersteltest. Wacht tot die klaar is; deze pagina volgt hem.',
  'admin.bak.err.notRestorable.status':
    'Deze back-up is niet geslaagd en dus niet terug te zetten. Kies een andere of maak een nieuwe.',
  'admin.bak.err.notRestorable.schemaNewer':
    'Deze back-up komt van een nieuwere versie van de server dan die nu draait. Zet hem terug met die nieuwere versie, of kies een oudere back-up.',
  'admin.bak.err.notRestorable.key':
    'De sleutel voor de geheimen van deze server past niet op deze back-up. Zet de wachtzin waarmee de back-up gemaakt is in PLEYA_SERVER_BACKUP_KEY en herstart; er is niets gewijzigd.',
  'admin.bak.err.notRestorable.unreadable':
    'Het back-upbestand is niet te lezen. Kijk in de back-upmap op de NAS; er is niets gewijzigd.',
  'admin.bak.err.notRestorable.fallback':
    'Deze back-up is niet terug te zetten. Er is niets gewijzigd. Kies een andere.',
  'admin.bak.err.confirmMismatch':
    'De bevestigingszin van deze back-up is veranderd sinds je de lijst opende. Laad opnieuw en probeer het nog eens; er is niets gewijzigd.',
  'admin.bak.err.maintenance':
    'De server zet een back-up terug en weigert alles tot hij herstart is. Wacht een paar minuten en laad opnieuw.',
  'admin.bak.err.gone': 'Deze back-up bestaat niet meer. Laad de lijst opnieuw.',
  'admin.bak.err.full':
    'De schijf van de back-upmap is vol. Maak ruimte of verlaag de bewaartermijn en probeer het opnieuw.',
  'admin.bak.err.fullCreate':
    'Er is geen ruimte meer om de back-up te schrijven. Maak ruimte vrij op de schijf van de back-upmap en probeer het opnieuw.',
  'admin.bak.err.restoreUnknown':
    'De server antwoordde niet. Het terugzetten kan toch begonnen zijn. Druk niet nog eens op Terugzetten: laad opnieuw en kijk in de lijst; zit de server in onderhoud, dan is hij bezig.'
} as const satisfies Record<keyof typeof webBackups, string>;
