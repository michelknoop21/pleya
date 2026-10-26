<!--
  Het toestellenwerk van scherm 27, los van UserEditor: één toestel uitloggen,
  Overal uitloggen en oude toestellen opruimen. Alle drie zijn losse
  `DELETE /sessions/{id}`-aanvragen, want het contract kent geen route die
  meer dan één sessie intrekt. Overal uitloggen en opruimen delen dezelfde rij
  (`revokeEach`): een fout stopt hem niet, en achteraf staat er hoeveel er
  lukte. Na elke actie wordt de lijst opnieuw gelezen.
-->
<script lang="ts">
  import type { AdminUsersApi, UserSession } from '../api/adminUsers';
  import type { User } from '../api/types';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import { t } from '../i18n';
  import DeviceCleanup from './DeviceCleanup.svelte';
  import { deviceLabel, revokeEach } from './sessionCleanup';
  import UserDevicesPanel from './UserDevicesPanel.svelte';
  import { userProblem, type UserProblem } from './userErrors';

  interface Props {
    user: User;
    /** Null als de sessies niet te lezen waren. */
    sessions: UserSession[] | null;
    usersApi: AdminUsersApi;
    /** De opnieuw gelezen lijst, of null als dat niet lukte. */
    onsessions: (sessions: UserSession[] | null) => void;
    onnotice: (text: string) => void;
    /** Een melding met de actie die het opnieuw probeert. */
    onproblem: (problem: UserProblem, again: () => void) => void;
    onclear: () => void;
  }

  let { user, sessions, usersApi, onsessions, onnotice, onproblem, onclear }: Props = $props();

  let revoking = $state<Record<string, boolean>>({});
  let allOpen = $state(false);
  let allBusy = $state(false);

  const items = $derived((sessions ?? []).map((session) => ({ session })));

  async function refresh(): Promise<void> {
    onsessions(await usersApi.sessionsOf(user.id).catch(() => null));
  }

  async function revokeOne(item: UserSession): Promise<void> {
    onclear();
    revoking[item.id] = true;
    try {
      await usersApi.revokeSession(item.id);
      await refresh();
      onnotice(t('admin.users.notice.signedOut', { device: deviceLabel(item) }));
    } catch (err) {
      onproblem(userProblem(err, user.username), () => void revokeOne(item));
      await refresh();
    } finally {
      revoking[item.id] = false;
    }
  }

  async function revokeAll(): Promise<void> {
    onclear();
    allBusy = true;
    const todo = (sessions ?? []).filter((s) => !s.current);
    const outcome = await revokeEach(todo, (item) => usersApi.revokeSession(item.id));
    await refresh();
    allBusy = false;
    allOpen = false;
    const name = user.username;
    if (outcome.failed.length === 0) {
      onnotice(t('admin.users.notice.signedOutAll', { name }));
    } else if (outcome.done.length === 0) {
      onproblem(userProblem(outcome.failed[0]!.error, name), () => (allOpen = true));
    } else {
      const message = t('admin.users.devices.allPartial', {
        name,
        done: outcome.done.length,
        total: todo.length,
        failed: outcome.failed.length
      });
      onproblem({ code: 'client.partial', message, wayOut: 'retry' }, () => (allOpen = true));
    }
  }
</script>

<UserDevicesPanel
  {sessions}
  {revoking}
  onrevoke={(item) => void revokeOne(item)}
  onrevokeAll={() => (allOpen = true)}
>
  {#snippet cleanup()}
    <DeviceCleanup {items} revoke={(id) => usersApi.revokeSession(id)} ondone={refresh} />
  {/snippet}
</UserDevicesPanel>

<ConfirmDialog
  bind:open={allOpen}
  busy={allBusy}
  title={t('admin.users.devices.allTitle', { name: user.username })}
  message={t('admin.users.devices.allBody', { name: user.username })}
  confirmLabel={t('admin.users.devices.signOutAll')}
  onconfirm={() => void revokeAll()}
/>
