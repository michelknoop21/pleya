<!--
  Serverbeheer, overzicht (northstar 20): kruimel en servernaam met de status
  rechts, een melding per niet-gemounte opslagroot, de vier tellers, en
  daaronder Activiteit naast Server en Nu aan het kijken (2fr 1fr vanaf 1200,
  daaronder één kolom).
-->
<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { t } from '../i18n';
  import { formatRelative } from '../util/format';
  import { session } from '../stores/session.svelte';
  import ActivityPanel from './ActivityPanel.svelte';
  import OverviewTiles from './OverviewTiles.svelte';
  import ServerPanel from './ServerPanel.svelte';
  import WatchingPanel from './WatchingPanel.svelte';
  import { storageSummary, type OverviewData } from './overview';

  let { data }: { data: OverviewData } = $props();

  const ready = $derived(data.server.health?.ready !== false);
  const status = $derived(
    t(ready ? 'admin.status.online' : 'admin.status.notReady', {
      version: data.server.version,
      since: formatRelative(data.server.started_at) ?? ''
    })
  );
  const unmounted = $derived(storageSummary(data.roots).unmounted);
</script>

<header class="head">
  <p class="crumb">{t('admin.title')}</p>
  <div class="title-row">
    <h1 class="title">{data.server.name}</h1>
    <StatusPill variant="dot" tone={ready ? 'ok' : 'warn'} label={status} />
  </div>
</header>

{#if unmounted.length > 0}
  <div class="alert">
    <Alert tone="warn" title={t('admin.alert.unmountedTitle')} live={false}>
      {#if unmounted.length === 1}
        {t('admin.alert.unmountedBody', { path: unmounted[0]!.path })}
      {:else}
        {t('admin.alert.unmountedMany', { count: unmounted.length })}
      {/if}
      {#snippet actions()}
        <a class="btn btn--secondary btn--sm" href="/admin/storage">{t('admin.alert.action')}</a>
      {/snippet}
    </Alert>
  </div>
{/if}

<OverviewTiles {data} />

<div class="cols">
  <ActivityPanel {data} />
  <div class="side">
    <ServerPanel {data} info={session.info} />
    <WatchingPanel {data} />
  </div>
</div>

<style>
  .head {
    margin-bottom: 18px;
  }

  .crumb {
    margin: 0 0 4px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .title-row {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px 16px;
  }

  /* Op 320 past "Online · versie … · gestart …" niet op één regel; de pil
     mag hier afbreken in plaats van de pagina breder te maken. */
  .title-row :global(.pill) {
    min-width: 0;
    white-space: normal;
  }

  .title {
    min-width: 0;
    margin: 0;
    font-size: 34px;
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .alert {
    margin-bottom: 16px;
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
    align-items: start;
    gap: 14px;
    margin-top: 16px;
  }

  .side {
    display: grid;
    gap: 14px;
    min-width: 0;
  }

  @media (max-width: 1199px) {
    .cols {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (max-width: 899px) {
    .title {
      font-size: 26px;
    }
  }
</style>
