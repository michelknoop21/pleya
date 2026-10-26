<!--
  Serverbeheer, gebruikers (northstar 26): kop met Gebruiker toevoegen, de
  tabel en de twee toelichtingen. Alleen lezen: elke wijziging staat op het
  scherm van één gebruiker (27). Een melding na toevoegen of verwijderen komt
  via de query.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Alert from '../components/Alert.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import { adminUsersApi } from '../api/adminUsers';
  import { describeError } from '../api/errors';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import UsersRolesPanel from './UsersRolesPanel.svelte';
  import UsersTable from './UsersTable.svelte';
  import { loadUsers, type UsersData } from './users';

  interface Props {
    /** Naam van een gebruiker die net verwijderd is (`?removed=`). */
    removed?: string | null;
    /** Naam van een gebruiker die net aangemaakt is (`?added=`). */
    added?: string | null;
  }

  let { removed = null, added = null }: Props = $props();

  let data = $state<UsersData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);

  const notice = $derived(
    removed
      ? t('admin.users.notice.removed', { name: removed })
      : added
        ? t('admin.users.notice.added', { name: added })
        : null
  );

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    failure = null;
    loadUsers(adminApi(session.client), adminUsersApi(session.client), controller.signal)
      .then((result) => {
        data = result;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        failure = describeError(err);
      });
    return () => controller.abort();
  });
</script>

<AdminPageHead
  title={t('admin.nav.users')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.users') }]}
>
  {#snippet actions()}
    <a class="btn btn--sm" href="/admin/users/new">
      <AdminIcon name="plus" size={16} />{t('admin.users.action.add')}
    </a>
  {/snippet}
</AdminPageHead>

{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}

{#if data}
  {#if data.entries.length === 0}
    <StateView title={t('admin.users.empty.title')} message={t('admin.users.empty.body')} />
  {:else}
    <UsersTable entries={data.entries} />
  {/if}
  <UsersRolesPanel />
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

<style>
  .msg {
    margin-bottom: 14px;
  }
</style>
