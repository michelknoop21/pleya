/**
 * De back-uproutes van het beheer (S25.6, scherm 35), in een eigen bestand
 * zodat `admin.ts` er niet bij groeit.
 *
 * Alles is klasse `admin`; een lid krijgt 404. Er is bewust geen route om een
 * back-up te downloaden, en dus ook geen knop: de map is voor de beheerder van
 * de NAS gewoon leesbaar. De back-upsleutel komt in geen enkel antwoord voor,
 * alleen `secrets_key_configured`.
 */
import type { PleyaClient } from './client';
import type { Backup, BackupList } from './types';

export function adminBackupsApi(client: PleyaClient) {
  return {
    list: (signal?: AbortSignal): Promise<BackupList> =>
      client.request((raw) => raw.GET('/backups', { signal })),

    /** 202 met de nieuwe rij op `running`; 409 `server.backup_busy` als er al een loopt. */
    create: (): Promise<Backup> => client.request((raw) => raw.POST('/backups')),

    /** Een hersteltest op een bestaande back-up; de echte database blijft onaangeraakt. */
    verify: (backupId: string): Promise<Backup> =>
      client.request((raw) =>
        raw.POST('/backups/{backup_id}/verify', { params: { path: { backup_id: backupId } } })
      ),

    /**
     * Zet een back-up terug. `confirm` is de zin uit `restore_confirmation`,
     * letterlijk; de server toetst hem zelf ook en geeft anders 409
     * `server.confirm_mismatch`. Na de 202 is de server in onderhoud en
     * herstart hij.
     */
    restore: (backupId: string, confirm: string): Promise<Backup> =>
      client.request((raw) =>
        raw.POST('/backups/{backup_id}/restore', {
          params: { path: { backup_id: backupId } },
          body: { confirm }
        })
      )
  };
}

export type AdminBackupsApi = ReturnType<typeof adminBackupsApi>;
