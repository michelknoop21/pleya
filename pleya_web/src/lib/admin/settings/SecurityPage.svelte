<!--
  Serverbeheer, beveiliging (northstar 31): de levensduur van tokens, de
  ingelogde toestellen van alle gebruikers, en de ondertekensleutel als
  bewuste noodgreep. Opslaan, een toestel intrekken en de sleutel roteren
  vragen elk hun eigen bevestiging.
-->
<script lang="ts">
  import { goto } from '$app/navigation';

  import { adminApi } from '../../api/admin';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { adminUsersApi } from '../../api/adminUsers';
  import { describeError } from '../../api/errors';
  import type { Settings } from '../../api/types';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import AdminColumns from './AdminColumns.svelte';
  import SecurityAgentsLink from './SecurityAgentsLink.svelte';
  import SecurityDevicesPanel from './SecurityDevicesPanel.svelte';
  import SecurityTokensPanel from './SecurityTokensPanel.svelte';
  import { deviceLabel } from '../sessionCleanup';
  import {
    draftFrom,
    loadDevices,
    loadSecurity,
    securityPatch,
    type DeviceRow,
    type SecurityData,
    type SecurityDraft
  } from './security';
  import { settingsProblem } from './settingsErrors';
  import SettingsSave from './SettingsSave.svelte';
  import { changeLines, securityRisks } from './settings';
  import SigningKeyPanel from './SigningKeyPanel.svelte';

  let data = $state<SecurityData | null>(null);
  let draft = $state<SecurityDraft>({ access: '', refresh: '' });
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});

  let revoking = $state<Record<string, boolean>>({});
  let revokeTarget = $state<DeviceRow | null>(null);
  let revokeOpen = $state(false);

  let rotateOpen = $state(false);
  let rotating = $state(false);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadSecurity(
      adminApi(session.client),
      adminUsersApi(session.client),
      adminSettingsApi(session.client),
      controller.signal
    )
      .then((result) => {
        data = result;
        draft = draftFrom(result.settings);
        failure = null;
      })
      .catch((err: unknown) => {
        if (!controller.signal.aborted) failure = describeError(err);
      });
    return () => controller.abort();
  });

  const patch = $derived(data ? securityPatch(data.settings, draft) : {});

  function saved(settings: Settings): void {
    if (data) data = { ...data, settings };
    draft = draftFrom(settings);
  }

  async function refreshDevices(): Promise<void> {
    try {
      const fresh = await loadDevices(adminApi(session.client), adminUsersApi(session.client));
      if (data) data = { ...data, ...fresh };
    } catch {
      // De lijst blijft staan zoals hij was; Opnieuw laden in de melding haalt hem op.
    }
  }

  function askRevoke(row: DeviceRow): void {
    revokeTarget = row;
    revokeOpen = true;
  }

  async function revoke(): Promise<void> {
    const row = revokeTarget;
    if (!row) return;
    revoking[row.session.id] = true;
    problem = null;
    try {
      await adminUsersApi(session.client).revokeSession(row.session.id);
      revokeOpen = false;
      if (data) data = { ...data, devices: data.devices.filter((d) => d.session.id !== row.session.id) };
    } catch (err) {
      revokeOpen = false;
      problem = settingsProblem(err, 'session', deviceLabel(row.session));
      retry = () => void revoke();
    } finally {
      revoking[row.session.id] = false;
    }
  }

  async function rotate(): Promise<void> {
    rotating = true;
    problem = null;
    try {
      await adminSettingsApi(session.client).rotateSigningKey();
      rotateOpen = false;
      // Elke sessie is ingetrokken, ook deze: lokaal uitloggen en opnieuw beginnen.
      await session.signOut({ local: true });
      await goto('/login');
    } catch (err) {
      rotateOpen = false;
      problem = settingsProblem(err, 'rotate');
      retry = () => (rotateOpen = true);
    } finally {
      rotating = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.nav.security')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.security') }]}
/>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={() => (attempt += 1)} />
  </div>
{/if}

{#if data}
  <AdminColumns>
    {#snippet left()}
      <SecurityTokensPanel settings={data!.settings} bind:draft />
      <SecurityAgentsLink />
    {/snippet}
    {#snippet right()}
      <SecurityDevicesPanel
        devices={data!.devices}
        unreadable={data!.unreadable}
        {revoking}
        onrevoke={askRevoke}
        cleanupRevoke={(id) => adminUsersApi(session.client).revokeSession(id)}
        oncleaned={refreshDevices}
      />
      <SigningKeyPanel busy={rotating} onrotate={() => (rotateOpen = true)} />
    {/snippet}
  </AdminColumns>

  <SettingsSave
    {patch}
    risks={securityRisks(patch)}
    lines={changeLines(patch)}
    onsaved={saved}
    oncancel={() => (draft = draftFrom(data!.settings))}
  />

  <ConfirmDialog
    bind:open={revokeOpen}
    busy={revokeTarget ? revoking[revokeTarget.session.id] : false}
    title={t('admin.sec.devices.revokeTitle', { device: revokeTarget ? deviceLabel(revokeTarget.session, true) : '' })}
    message={t('admin.sec.devices.revokeBody', { user: revokeTarget?.user.username ?? '' })}
    confirmLabel={t('admin.sec.devices.revoke')}
    onconfirm={() => void revoke()}
  />
  <ConfirmDialog
    bind:open={rotateOpen}
    busy={rotating}
    requirePhrase="rotate"
    phraseLabel={t('admin.sec.key.phraseLabel')}
    title={t('admin.sec.key.confirmTitle')}
    message={t('admin.sec.key.confirmBody')}
    confirmLabel={t('admin.sec.key.rotate')}
    onconfirm={() => void rotate()}
  />
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
