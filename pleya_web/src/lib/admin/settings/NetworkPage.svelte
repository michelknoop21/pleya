<!--
  Serverbeheer, netwerk en identiteit (northstar 30): servernaam, publiek adres,
  web-origin en CORS als instellingen, en de verbinding alleen-lezen met een
  test. Opslaan vraagt een bevestiging die noemt wat je kunt buitensluiten.

  Niet gebouwd omdat het contract het niet levert: de naam van de proxy waar de
  aanvraag door kwam en de TLS-regel. De tekstkaarten "Wat hier bewust niet
  staat" en "Zonder inloggen bereikbaar" zijn overgenomen; de tweede noemt de
  vier routes die in `openapi.yaml` `security: []` dragen.
-->
<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import { describeError } from '../../api/errors';
  import type { ConnectivityCheck, Settings } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import AdminColumns from './AdminColumns.svelte';
  import {
    draftFrom,
    loadNetwork,
    networkPatch,
    validate,
    type NetworkData,
    type NetworkDraft
  } from './network';
  import NetworkConnectionPanel from './NetworkConnectionPanel.svelte';
  import NetworkIdentityPanel from './NetworkIdentityPanel.svelte';
  import NetworkOriginsPanel from './NetworkOriginsPanel.svelte';
  import { settingsProblem } from './settingsErrors';
  import SettingsSave from './SettingsSave.svelte';
  import { changeLines, networkRisks } from './settings';

  const PUBLIC_ROUTES = [
    'GET /pleya/v1/info',
    'POST /pleya/v1/auth/setup',
    'POST /pleya/v1/auth/login',
    'POST /pleya/v1/auth/refresh'
  ];

  let data = $state<NetworkData | null>(null);
  let draft = $state<NetworkDraft>({ name: '', publicUrl: '', webOrigin: '', cors: '' });
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let check = $state<ConnectivityCheck | null>(null);
  let testing = $state(false);
  let problem = $state<LibraryProblem | null>(null);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadNetwork(session.client, adminSettingsApi(session.client), controller.signal)
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

  const errors = $derived(validate(draft));
  const blocked = $derived(Object.keys(errors).length > 0);
  const patch = $derived(data ? networkPatch(data.settings, draft) : {});
  const pageOrigin = typeof location === 'undefined' ? '' : location.origin;

  function saved(settings: Settings): void {
    if (data) data = { ...data, settings };
    draft = draftFrom(settings);
  }

  async function test(): Promise<void> {
    testing = true;
    problem = null;
    try {
      check = await adminSettingsApi(session.client).checkConnectivity();
    } catch (err) {
      problem = settingsProblem(err);
    } finally {
      testing = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.net.title')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.network') }]}
/>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => void test()} onreload={() => (attempt += 1)} />
  </div>
{/if}

{#if data}
  <AdminColumns>
    {#snippet left()}
      <NetworkIdentityPanel settings={data!.settings} serverId={data!.server.id} bind:draft {errors} />
      <NetworkOriginsPanel settings={data!.settings} bind:draft {errors} />
    {/snippet}
    {#snippet right()}
      <NetworkConnectionPanel
        server={data!.server}
        {check}
        busy={testing}
        publicUrlSet={data!.settings.public_url.value !== ''}
        ontest={() => void test()}
      />
      <Panel>
        {#snippet title()}{t('admin.net.not.title')}{/snippet}
        <p class="body">{t('admin.net.not.body')}</p>
      </Panel>
      <Panel>
        {#snippet title()}{t('admin.net.open.title')}{/snippet}
        <p class="body">{t('admin.net.open.intro')}</p>
        <ul class="routes">
          {#each PUBLIC_ROUTES as route (route)}<li class="mono">{route}</li>{/each}
        </ul>
      </Panel>
    {/snippet}
  </AdminColumns>

  <SettingsSave
    {patch}
    {blocked}
    risks={networkRisks(patch, pageOrigin)}
    lines={changeLines(patch)}
    onsaved={saved}
    oncancel={() => (draft = draftFrom(data!.settings))}
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

  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .routes {
    display: grid;
    gap: 5px;
    margin: 10px 0 0;
    padding: 0;
    list-style: none;
    font-size: 13px;
    color: var(--ink-2);
    overflow-wrap: anywhere;
  }
</style>
