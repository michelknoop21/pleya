<!--
  Scherm 27: één gebruiker. Rol, bibliotheken, toestellen, account en
  verwijderen, met Annuleren en Opslaan onderaan. Rol en rechten gaan in
  één Opslaan, maar als twee aanvragen (`PATCH /users/{id}` eerst, dan
  `PUT /users/{id}/permissions`), zodat de server de nieuwe rol kent als hij de
  rechten toetst.

  Bevestigen is hier geen versiering: een rol die rechten afneemt, en het
  vervangen van de rechtenlijst, gaan nooit zonder dialoog door. Het
  vervangen is nodig omdat de huidige rechten niet te lezen zijn (zie
  UserPermissionsPanel). Een eigen degradatie waarschuwt dat het beheer
  daarna dicht gaat, en na het opslaan laadt de sessie opnieuw.

  Weggelaten omdat het contract het niet draagt: aangemaakt op, hernoemen,
  een uitgeschakelde staat voor een gebruiker, en een route om alle sessies in
  één keer in te trekken. Het toestellenwerk staat in UserDevices.
-->
<script lang="ts">
  import { goto } from '$app/navigation';

  import { adminApi } from '../api/admin';
  import { adminUsersApi } from '../api/adminUsers';
  import { describeError } from '../api/errors';
  import type { Role } from '../api/types';
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { plural, t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import UserAccountPanel from './UserAccountPanel.svelte';
  import UserDeletePanel from './UserDeletePanel.svelte';
  import UserDevices from './UserDevices.svelte';
  import UserPermissionsPanel from './UserPermissionsPanel.svelte';
  import UserProblemAlert from './UserProblemAlert.svelte';
  import UserRolePanel from './UserRolePanel.svelte';
  import { userProblem, type UserProblem } from './userErrors';
  import {
    clampForRole,
    deviceSessions,
    grantLines,
    grantsFrom,
    hasChanges,
    loadUserDetail,
    roleLabel,
    savePlan,
    seesEverything,
    type Grants,
    type SavePlan,
    type UserDetail
  } from './users';

  interface Props {
    id: string;
    /** Naam van een gebruiker die net is aangemaakt (`?added=`). */
    added?: string | null;
  }

  let { id, added = null }: Props = $props();

  const LIST = '/admin/users';
  const usersApi = $derived(adminUsersApi(session.client));

  let detail = $state<UserDetail | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);

  let chosen = $state<string>('member');
  let grants = $state<Grants>({});
  let touched = $state(false);
  let confirmedByServer = $state(false);

  let saving = $state(false);
  let problem = $state<UserProblem | null>(null);
  let retry = $state<(() => void) | null>(null);
  let notice = $state<string | null>(null);
  let resetBusy = $state(false);

  let saveOpen = $state(false);
  let deleteOpen = $state(false);
  let deleting = $state(false);

  $effect(() => {
    if (added) notice = t('admin.users.notice.added', { name: added });
  });

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    failure = null;
    loadUserDetail(session.client, adminApi(session.client), usersApi, id, controller.signal)
      .then((result) => {
        detail = result;
        if (result.user) chosen = result.user.role === 'owner' ? 'admin' : result.user.role;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        failure = describeError(err);
      });
    return () => controller.abort();
  });

  // Een beperkte gebruiker kan geen Beheren dragen: een al gezet vinkje zakt
  // naar Downloaden zodra de rol Beperkt gekozen wordt.
  $effect(() => {
    grants = clampForRole(grants, chosen as Role);
  });

  const user = $derived(detail?.user ?? null);
  const name = $derived(user?.username ?? '');
  const isSelf = $derived(user !== null && session.me?.id === user.id);
  const plan = $derived<SavePlan | null>(
    user
      ? savePlan({
          current: user.role,
          chosen: user.role === 'owner' ? 'owner' : (chosen as Role),
          grants,
          touched,
          libraries: detail?.libraries ?? []
        })
      : null
  );
  const dirty = $derived(plan !== null && hasChanges(plan));
  const deviceCount = $derived(detail?.sessions ? deviceSessions(detail.sessions).length : null);

  function fail(err: unknown, again: () => void): void {
    notice = null;
    problem = userProblem(err, name);
    retry = again;
  }

  function reload(): void {
    problem = null;
    notice = null;
    attempt += 1;
  }

  function requestSave(): void {
    if (!plan || !hasChanges(plan) || saving) return;
    if (plan.needsConfirm) saveOpen = true;
    else void apply();
  }

  async function apply(): Promise<void> {
    if (!plan || !user) return;
    const todo = plan;
    problem = null;
    saving = true;
    try {
      if (todo.role) {
        const updated = await usersApi.updateUser(user.id, { role: todo.role });
        detail = { ...detail!, user: updated };
      }
      if (todo.permissions) {
        const stored = await usersApi.setPermissions(user.id, todo.permissions);
        grants = grantsFrom(stored);
        touched = false;
        confirmedByServer = true;
      }
      notice = t('admin.users.notice.saved', { name });
      if (isSelf && todo.lowering && !seesEverything(todo.role ?? 'admin')) {
        await session.load();
        await goto('/');
      }
    } catch (err) {
      fail(err, requestSave);
    } finally {
      saving = false;
      saveOpen = false;
    }
  }

  async function resetPassword(password: string): Promise<boolean> {
    if (!user) return false;
    problem = null;
    resetBusy = true;
    try {
      await usersApi.updateUser(user.id, { password });
      notice = t('admin.users.notice.passwordSet', { name });
      return true;
    } catch (err) {
      fail(err, () => {});
      return false;
    } finally {
      resetBusy = false;
    }
  }

  async function remove(): Promise<void> {
    if (!user) return;
    problem = null;
    deleting = true;
    try {
      await usersApi.deleteUser(user.id);
      deleteOpen = false;
      await goto(`${LIST}?removed=${encodeURIComponent(user.username)}`);
    } catch (err) {
      deleteOpen = false;
      fail(err, () => (deleteOpen = true));
    } finally {
      deleting = false;
    }
  }
</script>

{#if user && detail}
  <AdminPageHead
    title={user.username}
    crumbs={[
      { label: t('admin.title'), href: '/admin' },
      { label: t('admin.nav.users'), href: LIST },
      { label: user.username }
    ]}
  >
    {#snippet actions()}
      {#if deviceCount !== null}
        <StatusPill
          variant="dot"
          tone={deviceCount > 0 ? 'ok' : 'idle'}
          label={deviceCount > 0
            ? plural('admin.users.signedIn', deviceCount)
            : t('admin.users.signedIn.none')}
        />
      {/if}
    {/snippet}
  </AdminPageHead>

  {#if notice}
    <div class="msg"><Alert tone="info">{notice}</Alert></div>
  {/if}
  {#if problem}
    <div class="msg">
      <UserProblemAlert {problem} onretry={() => retry?.()} onreload={reload} />
    </div>
  {/if}

  <div class="cols">
    <form
      class="main"
      onsubmit={(e) => {
        e.preventDefault();
        requestSave();
      }}
    >
      <UserRolePanel current={user.role} bind:chosen />
      <UserPermissionsPanel
        {name}
        role={user.role === 'owner' ? 'owner' : (chosen as Role)}
        libraries={detail.libraries}
        bind:grants
        bind:touched
        {confirmedByServer}
      />
    </form>
    <div class="side">
      <UserDevices
        {user}
        sessions={detail.sessions}
        {usersApi}
        onsessions={(sessions) => {
          if (detail) detail = { ...detail, sessions };
        }}
        onnotice={(text) => (notice = text)}
        onproblem={(found, again) => {
          notice = null;
          problem = found;
          retry = again;
        }}
        onclear={() => (problem = null)}
      />
      <UserAccountPanel
        username={user.username}
        canReset={user.role !== 'owner' || isSelf}
        busy={resetBusy}
        onreset={resetPassword}
      />
      <UserDeletePanel
        username={user.username}
        blocked={user.role === 'owner' ? 'owner' : isSelf ? 'self' : null}
        busy={deleting}
        bind:open={deleteOpen}
        onconfirm={() => void remove()}
      />
    </div>
    <div class="foot">
      <a class="btn btn--ghost" href={LIST}>{t('dialog.cancel')}</a>
      <button
        type="button"
        class="btn"
        disabled={!dirty || saving}
        aria-busy={saving ? 'true' : undefined}
        onclick={requestSave}
      >
        {t('admin.users.action.save')}
      </button>
    </div>
  </div>
{:else if detail}
  <StateView kind="error" title={t('admin.users.missing.title')} message={t('admin.users.missing.body')}>
    {#snippet actions()}
      <a class="btn btn--secondary btn--sm" href={LIST}>{t('admin.users.action.toList')}</a>
    {/snippet}
  </StateView>
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

{#if user && detail && plan}
  <ConfirmDialog
    bind:open={saveOpen}
    danger={plan.lowering}
    busy={saving}
    title={t('admin.users.save.confirmTitle', { name })}
    message={plan.lowering
      ? t('admin.users.save.lowering', {
          name,
          from: roleLabel(user.role),
          to: roleLabel(plan.role ?? user.role)
        })
      : undefined}
    confirmLabel={t('admin.users.save.confirm')}
    onconfirm={() => void apply()}
  >
    {#if plan.lowering && isSelf}
      <p class="dlg">{t('admin.users.save.self')}</p>
    {/if}
    {#if plan.permissions}
      {@const lines = grantLines(grants, detail.libraries)}
      <p class="dlg">{t('admin.users.save.replace', { name })}</p>
      {#if lines.length > 0}
        <ul class="dlg">
          {#each lines as line (line)}<li>{line}</li>{/each}
        </ul>
      {:else}
        <p class="dlg"><b>{t('admin.users.save.replaceNone', { name })}</b></p>
      {/if}
    {/if}
  </ConfirmDialog>
{/if}

<style>
  .msg {
    margin-bottom: 14px;
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
    align-items: start;
    gap: 14px;
  }

  .main,
  .side {
    display: grid;
    gap: 14px;
    min-width: 0;
  }

  .foot {
    grid-column: 1 / -1;
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 6px;
  }

  .dlg {
    margin: 10px 0 0;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  ul.dlg {
    list-style: disc;
    padding-left: 20px;
  }

  @media (max-width: 1199px) {
    .cols {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (max-width: 899px) {
    .foot .btn {
      flex: 1 1 auto;
    }
  }
</style>
