/**
 * Teksten van Onderhoud en back-ups (S25.6, scherm 35), in een eigen bestand
 * zodat `web.ts` niet bij elk beheerscherm groeit. `web.ts` spreidt dit
 * object; de Nederlandse helft staat in `webBackups.nl.ts`.
 */
export const webBackups = {
  'admin.bak.title': 'Maintenance',
  'admin.bak.link': 'Maintenance and backups',
  'admin.bak.create': 'Back up now',
  'admin.bak.creating': 'Starting…',
  'admin.bak.notice.created': 'The backup is queued. This page follows it until it is done.',
  'admin.bak.notice.verifying': 'The restore test is queued. This page follows it until it is done.',
  'admin.bak.unsupported.title': 'This server does not make backups',
  'admin.bak.unsupported.body':
    'The server does not offer backups (capabilities.backups is off). Update the server to a version that does.',

  'admin.bak.list.title': 'Backups',
  'admin.bak.list.summary': '{dir} · daily at {time} · {days} kept',
  'admin.bak.days.one': '{count} day',
  'admin.bak.days.other': '{count} days',
  'admin.bak.titles.one': '{count} title',
  'admin.bak.titles.other': '{count} titles',
  'admin.bak.empty': 'There are no backups yet. The first one is made at {time}, or press Back up now.',
  'admin.bak.col.made': 'Made',
  'admin.bak.col.content': 'Contents',
  'admin.bak.col.size': 'Size',
  'admin.bak.col.status': 'Status',
  'admin.bak.col.test': 'Restore test',
  'admin.bak.col.actions': 'Actions',
  'admin.bak.size.unknown': 'unknown',
  'admin.bak.explain':
    'A backup holds the database and the files from /config. The signing key is in it only encrypted, and only when a key is set. Media files are never in it. The restore test puts the backup back into a separate, temporary database and counts the titles, users, libraries and watch state; the real database is not touched.',

  'admin.bak.status.ok': 'ok',
  'admin.bak.status.running': 'running',
  'admin.bak.status.failed': 'failed',
  'admin.bak.status.missing': 'file missing',
  'admin.bak.trigger.schedule': 'daily',
  'admin.bak.trigger.manual': 'manual',
  'admin.bak.trigger.upgrade': 'before an upgrade',
  'admin.bak.content.database': 'database and /config',
  'admin.bak.content.schema': 'database (schema {schema}) and /config',
  'admin.bak.secrets.in': 'secrets included, encrypted',
  'admin.bak.secrets.out': 'without secrets',
  'admin.bak.test.never': 'not tested',
  'admin.bak.test.running': 'testing',
  'admin.bak.test.ok': 'restore test passed',
  'admin.bak.test.failed': 'restore test failed',
  'admin.bak.test.counted': '{found} of {expected} titles',
  'admin.bak.failure.storageFull': 'the disk was full',
  'admin.bak.failure.database': 'the database was not reachable',
  'admin.bak.failure.code': 'the server reported {code}',
  'admin.bak.failure.unknown': 'the server gave no reason',

  'admin.bak.action.verify': 'Restore test',
  'admin.bak.action.verifyFor': 'Run a restore test on the backup of {when}',
  'admin.bak.action.restore': 'Restore',
  'admin.bak.action.restoreFor': 'Restore the backup of {when}',
  'admin.bak.action.busy': 'A backup or restore test is running. Wait until it is done.',

  'admin.bak.settings.title': 'Settings',
  'admin.bak.settings.help':
    'These come from the environment of the server and cannot be changed here: a retention that can be lowered through the web could also be lowered by someone who took over an admin account. Change them in the compose file or on the NAS and restart the server.',
  'admin.bak.settings.dir': 'Folder',
  'admin.bak.settings.time': 'Time',
  'admin.bak.settings.timeValue': 'every day at {time}',
  'admin.bak.settings.retention': 'Retention',
  'admin.bak.settings.retentionNote': 'The newest successful backup is always kept.',
  'admin.bak.settings.key': 'Secrets key',
  'admin.bak.settings.keySet': 'set',
  'admin.bak.settings.keyNotSet': 'not set',

  'admin.bak.warn.failed.title': 'The last backup failed',
  'admin.bak.warn.failed.body':
    'Reason: {reason}. The older backups are still there. Fix the cause and press Back up now.',
  'admin.bak.warn.domain.title': 'The backup folder is on the same disk as the configuration',
  'admin.bak.warn.domain.body':
    '{dir} sits on the same file system as /config. A backup there protects against a failed upgrade or a wrong action, but not against a broken disk. Point the folder at another disk or a NAS share.',
  'admin.bak.warn.noKey.title': 'No key set for the secrets',
  'admin.bak.warn.noKey.body':
    'Without {variable} the secrets from /config stay out of a backup. After a restore on an empty server everyone has to sign in again. Set a passphrase of at least sixteen characters and keep it outside the NAS.',
  'admin.bak.warn.testNever.title': 'No backup has been restore-tested yet',
  'admin.bak.warn.testNever.body':
    'A backup is only a backup once it has been put back. Press Restore test on the newest backup; the server also does this weekly by itself.',
  'admin.bak.warn.testOld.title': 'The last restore test is too old',
  'admin.bak.warn.testOld.body':
    'The last successful restore test is more than {days} days old. The server runs one weekly after the scheduled backup, so something may be stuck. Press Restore test on the newest backup.',
  'admin.bak.warn.missing.title': 'A backup file is missing',
  'admin.bak.warn.missing.body.one':
    '{count} backup disappeared from {dir} without the server removing it. Was the folder moved or cleaned?',
  'admin.bak.warn.missing.body.other':
    '{count} backups disappeared from {dir} without the server removing them. Was the folder moved or cleaned?',

  'admin.bak.restore.title': 'Restore',
  'admin.bak.restore.body':
    'Puts the server in maintenance mode, loads the database and /config from the chosen backup and restarts. Watch state, users, sessions, settings and scans from after that backup are lost. That is why Restore is only offered on a backup that succeeded.',
  'admin.bak.restore.older':
    'A backup from a newer schema than this server cannot be restored; the server refuses it and says so.',
  'admin.bak.restore.confirmTitle': 'Restore the backup of {when}?',
  'admin.bak.restore.confirmBody':
    'This replaces the current data and cannot be undone. Make a new backup first if you want to keep what is there now.',
  'admin.bak.restore.lose': 'What happens, in this order:',
  'admin.bak.restore.step1':
    'The server checks the backup. If anything is wrong it stops here and nothing changes.',
  'admin.bak.restore.step2':
    'The server goes into maintenance mode: every request is refused and streams stop.',
  'admin.bak.restore.step3':
    'The database and /config are replaced by the backup. Everything after it is lost: watch state, users, sessions, settings and scans.',
  'admin.bak.restore.step4':
    'The server restarts by itself. You and other signed-in users may have to sign in again.',
  'admin.bak.restore.sentence': 'Type this sentence exactly to confirm:',
  'admin.bak.restore.phrase': 'Confirmation sentence',
  'admin.bak.restore.confirm': 'Restore this backup',

  'admin.bak.wait.title': 'The server is restoring the backup',
  'admin.bak.wait.body':
    'This takes a few minutes and the server is not reachable meanwhile. This page checks every few seconds whether it answers again. You can close the tab; the server carries on.',
  'admin.bak.back.title': 'The server answers again',
  'admin.bak.back.body':
    'The restore is done, or it failed and the server runs on the database it had before (it restarts either way). Check the list and the server log under Diagnostics to see which.',
  'admin.bak.back.list': 'To the list',
  'admin.bak.back.log': 'Server log',
  'admin.bak.signin.title': 'Sign in again',
  'admin.bak.signin.body':
    'The server is back, but your session is not in the restored database. Sign in again to see the result.',
  'admin.bak.signin.action': 'Sign in',
  'admin.bak.timeout.title': 'The server does not answer yet',
  'admin.bak.timeout.body':
    'After ten minutes there is still no answer. The server restarts through the restart policy of its container; if it is stopped, start it on the NAS and read its log. Do not start a second restore.',
  'admin.bak.timeout.action': 'Check again',

  'admin.bak.err.busy':
    'A backup or restore test is already queued or running. Wait until it is done; this page follows it.',
  'admin.bak.err.notRestorable.status':
    'This backup did not succeed, so it cannot be restored. Pick another one or make a new backup.',
  'admin.bak.err.notRestorable.schemaNewer':
    'This backup is from a newer version of the server than the one running. Restore it with that newer version, or pick an older backup.',
  'admin.bak.err.notRestorable.key':
    'The secrets key of this server does not fit this backup. Set the passphrase the backup was made with in PLEYA_SERVER_BACKUP_KEY and restart; nothing was changed.',
  'admin.bak.err.notRestorable.unreadable':
    'The backup file cannot be read. Look in the backup folder on the NAS; nothing was changed.',
  'admin.bak.err.notRestorable.fallback':
    'This backup cannot be restored. Nothing was changed. Pick another one.',
  'admin.bak.err.confirmMismatch':
    'The confirmation sentence of this backup has changed since you opened the list. Reload and try again; nothing was changed.',
  'admin.bak.err.maintenance':
    'The server is restoring a backup and refuses everything until it has restarted. Wait a few minutes and reload.',
  'admin.bak.err.gone': 'This backup no longer exists. Reload the list.',
  'admin.bak.err.full':
    'The disk of the backup folder is full. Free up space or lower the retention, then try again.',
  'admin.bak.err.fullCreate':
    'There is no room left to write the backup. Free up space on the disk of the backup folder, then try again.',
  'admin.bak.err.restoreUnknown':
    'The server did not answer. The restore may have started anyway. Do not press Restore again: reload and look at the list; if the server is in maintenance it is working.'
} as const;
