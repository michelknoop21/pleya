/**
 * Teksten over toestellen en sessies (DEC-164): de naam die deze browser bij
 * het inloggen meestuurt, de weergave van een toestel zonder naam, en het
 * opruimen van oude toestellen op de schermen 27 en 31. `web.ts` spreidt dit
 * object; de Nederlandse helft staat in `webSessions.nl.ts`.
 */
export const webSessions = {
  'device.browser': 'Browser',
  'device.browserOn': '{browser} on {platform}',

  'admin.devices.unknown': 'Unknown device',
  'admin.devices.unknownSince': 'Unknown device, signed in {date}',
  'admin.devices.signedInOn': 'signed in {date}',

  'admin.devices.cleanup.open': 'Clean up old devices',
  'admin.devices.cleanup.title': 'Clean up old devices?',
  'admin.devices.cleanup.body':
    'Signs out every device that has not been seen for longer than the period you choose. The device you are using now and API tokens stay signed in.',
  'admin.devices.cleanup.period': 'Not seen for more than',
  'admin.devices.cleanup.days': '{count} days',
  'admin.devices.cleanup.count.one': '{count} device will be signed out:',
  'admin.devices.cleanup.count.other': '{count} devices will be signed out:',
  'admin.devices.cleanup.none': 'No device has gone unseen for that long. Choose a shorter period or close this window.',
  'admin.devices.cleanup.item': '{device} · seen {seen}',
  'admin.devices.cleanup.itemOf': '{user}: {device} · seen {seen}',
  'admin.devices.cleanup.more': 'and {count} more',
  'admin.devices.cleanup.confirm.one': 'Sign out {count} device',
  'admin.devices.cleanup.confirm.other': 'Sign out {count} devices',
  'admin.devices.cleanup.progress': '{done} of {total} signed out',
  'admin.devices.cleanup.done.one': '{count} old device signed out.',
  'admin.devices.cleanup.done.other': '{count} old devices signed out.',
  'admin.devices.cleanup.partial':
    '{done} of {total} devices signed out. {failed} could not be signed out; the list shows what is still there. Try again for the rest, or reload the page if it keeps failing.',
  'admin.devices.cleanup.retry': 'Try again',

  'admin.users.devices.allPartial':
    '{done} of {total} sessions of {name} signed out. {failed} could not be signed out; the list shows what is still there. Try again for the rest.'
} as const;
