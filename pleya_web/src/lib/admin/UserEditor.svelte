<!--
  De pagina van één gebruiker (scherm 27, herzien): een kop met naam, rol en
  toestellen, en drie tabs. Profiel draagt het account en het wachtwoord,
  Toegang de rol en de bibliotheekrechten, Toestellen de sessies. Verwijderen
  staat onder elke tab. Wachtwoord opnieuw instellen en Opslaan staan in de
  kop; de eerste opent het formulier op de tab Profiel.

  Rol en rechten gaan in één Opslaan, maar als twee aanvragen (`PATCH
  /users/{id}` eerst, dan `PUT /users/{id}/permissions`), zodat de server de
  nieuwe rol kent als hij de rechten toetst. Een tabwissel gooit niets weg: de
  gekozen rol en rechten leven hier en niet in de tab.

  Bevestigen is hier geen versiering: een rol die rechten afneemt, en het
  vervangen van de rechtenlijst, gaan nooit zonder dialoog door. Het
  vervangen is nodig omdat de huidige rechten niet te lezen zijn (zie
  UserPermissionsPanel). Een eigen degradatie waarschuwt dat het beheer
  daarna dicht gaat, en na het opslaan laadt de sessie opnieuw.

  Weggelaten omdat het contract het niet draagt: aangemaakt op, hernoemen,
  een uitgeschakelde staat voor een gebruiker, een leeftijdsgrens of
  kijktijden, rechten kopiëren van een ander, en een route om alle sessies in
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
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import UserAccountPanel from './UserAccountPanel.svelte';
  import UserDeletePanel from './UserDeletePanel.svelte';
  import UserDevices from './UserDevices.svelte';
  import UserHead from './UserHead.svelte';
  import UserPermissionsPanel from './UserPermissionsPanel.svelte';
  import UserProblemAlert from './UserProblemAlert.svelte';
  import UserRolePanel from './UserRolePanel.svelte';
  import UserTabs from './UserTabs.svelte';
  import { userProblem, type UserProblem } from './userErrors';
  import {
    clampForRole,
    grantLines,
    grantsFrom,
    hasChanges,
    loadUserDetail,
    parseTab,
    roleLabel,
    savePlan,
    seesEverything,
    type Grants,
    type SavePlan,
    type UserDetail,
    type UserTab
  } from './users';

  interface Props {
    id: string;
    /** Naam van een gebruiker die net is aangemaakt (`?added=`). */
    added?: string | null;
    /** De tab uit `?tab=`; zonder waarde Toegang. */
    tab?: string | null;
  }

  let { id, added = null, tab: tabParam = null }: Props = $props();

  const LIST = '/admin/users';
  const FORM = 'user-access-form';
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
  let resetOpen = $state(false);
  let tab = $state<UserTab>('access');

  let saveOpen = $state(false);
  let deleteOpen = $state(false);
  let deleting = $state(false);

  $effect(() => {
    if (added) notice = t('admin.users.notice.added', { name: added });
  });

  $effect(() => {
    tab = parseTab(tabParam);
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

  // Een beperkte gebruiker kan geen Beheren dragen: een al gekozen Beheren zakt
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

  function select(next: UserTab): void {
    tab = next;
    // Een melding met "Opnieuw proberen" hoort bij het paneel dat hem gaf; dat
    // paneel bestaat na de wissel niet meer, dus de melding gaat mee weg.
    problem = null;
    retry = null;
    // De query volgt de tab, zodat herladen op dezelfde tab blijft; `reset: false`
    // houdt de scrollstand en de focus op de aangeklikte tab.
    void goto(`?tab=${next}`, { replaceState: true, reset: false });
  }

  function openReset(): void {
    resetOpen = true;
    if (tab !== 'profile') select('profile');
  }

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
  <div class="page">
    <UserHead
      {user}
      sessions={detail.sessions}
      listHref={LIST}
      canReset={user.role !== 'owner' || isSelf}
      {dirty}
      {saving}
      onreset={openReset}
      formId={FORM}
    />

    {#if notice}
      <div class="msg"><Alert tone="info">{notice}</Alert></div>
    {/if}
    {#if problem}
      <div class="msg">
        <UserProblemAlert {problem} onretry={() => retry?.()} onreload={reload} />
      </div>
    {/if}

    <UserTabs active={tab} onselect={select} />

    <div class="body">
      <!-- Alle drie de tabs blijven bestaan en worden verborgen: een lopende
           intrekking of een open wachtwoordformulier overleeft zo een tabwissel. -->
      <div class="pane" hidden={tab !== 'profile'}>
        <UserAccountPanel
          username={user.username}
          canReset={user.role !== 'owner' || isSelf}
          busy={resetBusy}
          bind:open={resetOpen}
          onreset={resetPassword}
        />
      </div>
      <!-- Het formulier geeft Enter op een keuze terug als opslaan; de knop
           Opslaan in de kop hoort er via `form` bij. -->
      <form
        id={FORM}
        class="pane"
        hidden={tab !== 'access'}
        novalidate
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
      <div class="pane" hidden={tab !== 'devices'}>
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
      </div>
      <UserDeletePanel
        username={user.username}
        blocked={user.role === 'owner' ? 'owner' : isSelf ? 'self' : null}
        busy={deleting}
        bind:open={deleteOpen}
        onconfirm={() => void remove()}
      />
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
      : plan.role
        ? t('admin.users.save.raising', { name, from: roleLabel(user.role), to: roleLabel(plan.role) })
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

  /* Eén kolom, begrensd: op 1920 staat een segmentkeuze anders een hele
     schermbreedte van zijn bibliotheek af, en de knoppen in de kop van de naam. */
  .page {
    max-width: 1040px;
  }

  .body {
    display: grid;
    gap: 14px;
  }

  .pane {
    display: grid;
    gap: 14px;
    margin: 0;
  }

  .pane[hidden] {
    display: none;
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
</style>
