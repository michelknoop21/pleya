/** De Nederlandse helft van `webSessions.ts` (DEC-164). Je-vorm, kort. */
import type { webSessions } from './webSessions';

export const webSessionsNl = {
  'device.browser': 'Browser',
  'device.browserOn': '{browser} op {platform}',

  'admin.devices.unknown': 'Onbekend toestel',
  'admin.devices.unknownSince': 'Onbekend toestel, aangemeld op {date}',
  'admin.devices.signedInOn': 'aangemeld op {date}',

  'admin.devices.cleanup.open': 'Oude toestellen opruimen',
  'admin.devices.cleanup.title': 'Oude toestellen opruimen?',
  'admin.devices.cleanup.body':
    'Logt elk toestel uit dat langer dan de gekozen periode niet gezien is. Het toestel waarmee je nu werkt en API-tokens blijven ingelogd.',
  'admin.devices.cleanup.period': 'Niet gezien in meer dan',
  'admin.devices.cleanup.days': '{count} dagen',
  'admin.devices.cleanup.count.one': '{count} toestel wordt uitgelogd:',
  'admin.devices.cleanup.count.other': '{count} toestellen worden uitgelogd:',
  'admin.devices.cleanup.none': 'Geen toestel is zo lang niet gezien. Kies een kortere periode of sluit dit venster.',
  'admin.devices.cleanup.item': '{device} · gezien {seen}',
  'admin.devices.cleanup.itemOf': '{user}: {device} · gezien {seen}',
  'admin.devices.cleanup.more': 'en nog {count}',
  'admin.devices.cleanup.confirm.one': '{count} toestel uitloggen',
  'admin.devices.cleanup.confirm.other': '{count} toestellen uitloggen',
  'admin.devices.cleanup.progress': '{done} van {total} uitgelogd',
  'admin.devices.cleanup.done.one': '{count} oud toestel uitgelogd.',
  'admin.devices.cleanup.done.other': '{count} oude toestellen uitgelogd.',
  'admin.devices.cleanup.partial':
    '{done} van {total} toestellen uitgelogd. Bij {failed} lukte het niet; de lijst toont wat er nog staat. Probeer het opnieuw voor de rest, of laad de pagina opnieuw als het blijft mislukken.',
  'admin.devices.cleanup.retry': 'Opnieuw proberen',

  'admin.users.devices.allPartial':
    '{done} van {total} sessies van {name} uitgelogd. Bij {failed} lukte het niet; de lijst toont wat er nog staat. Probeer het opnieuw voor de rest.'
} satisfies Record<keyof typeof webSessions, string>;
