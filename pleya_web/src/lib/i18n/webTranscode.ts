/**
 * Teksten van Transcode-sessies (scherm 37, S18.5), in een eigen bestand zodat
 * `web.ts` niet bij elk beheerscherm groeit. `web.ts` spreidt dit object; de
 * Nederlandse helft staat in `webTranscode.nl.ts`. Het stopvenster en de
 * modusnamen komen van scherm 28 (`admin.media.transcode.*`).
 */
export const webTranscode = {
  'admin.tc.title': 'Transcode sessions',
  'admin.tc.refresh': 'Refresh',
  'admin.tc.tile.busy': 'In use',
  'admin.tc.tile.busySub.one': '{count} session running',
  'admin.tc.tile.busySub.other': '{count} sessions running',
  'admin.tc.tile.busyNone': 'nothing is transcoding',
  'admin.tc.tile.max': 'Maximum',
  'admin.tc.tile.maxOff': 'off',
  'admin.tc.tile.maxSub': 'set by the server environment',
  'admin.tc.tile.maxOffSub': 'a maximum of 0 turns transcoding off',
  'admin.tc.tile.hardware': 'Hardware',
  'admin.tc.tile.software': 'Software',
  'admin.tc.tile.hardwareSub': 'detected at startup',
  'admin.tc.full.title': 'The server is at its maximum.',
  'admin.tc.full.body': 'A new request gets playback.transcode_busy and has to wait or play another way. Running sessions are never stopped to make room.',
  'admin.tc.full.action': 'Where the maximum is set',
  'admin.tc.off.title': 'Transcoding is off.',
  'admin.tc.off.body': 'This server reports no transcoder, so no session can run. The maximum and the hardware are on Media and streaming.',
  'admin.tc.running.title': 'Running',
  'admin.tc.running.empty': 'No transcode sessions are running.',
  'admin.tc.running.refresh': 'The list refreshes every five seconds while a session runs.',
  'admin.tc.running.foot': 'A session whose player stops sending heartbeats is cleaned up by the server. Stopping interrupts the viewer: the player gets an error and has to start again.',
  'admin.tc.col.user': 'User',
  'admin.tc.col.mode': 'Conversion',
  'admin.tc.col.started': 'Started',
  'admin.tc.col.heartbeat': 'Last heartbeat',
  'admin.tc.col.actions': 'Actions',
  'admin.tc.version': 'version {id}',
  'admin.tc.stopping': 'Stopping',
  'admin.tc.panelLink': 'All sessions'
} as const;
