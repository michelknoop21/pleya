<!--
  Serverbeheer op een telefoon (northstar 33): de zijbalk wordt een lijst.
  Bovenaan een melding als een opslagroot weg is en twee kleine tellers, dan
  de groepen Beheer en Instellingen. Afwijking van 33: Beheer begint met een
  rij Overzicht, zodat het volledige overzicht (20 op 393) ook op een telefoon
  bereikbaar is.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Alert from '../components/Alert.svelte';
  import { t } from '../i18n';
  import { formatBytes } from '../util/format';
  import { ADMIN_OVERVIEW_PATH, ADMIN_SECTIONS, type AdminSection } from './sections';
  import {
    countLabel,
    currentScan,
    libraryTitle,
    storageSummary,
    type OverviewData
  } from './overview';

  let { data }: { data: OverviewData } = $props();

  const storage = $derived(storageSummary(data.roots));
  const scan = $derived(currentScan(data.scans));
  const failedJobs = $derived(data.jobs.filter((j) => j.state === 'failed').length);

  const scanValue = $derived(
    scan?.active
      ? t(scan.scan.state === 'queued' ? 'admin.state.queued' : 'admin.state.running')
      : t('admin.tile.scanIdle')
  );
  const scanSub = $derived(
    scan ? (libraryTitle(data.libraries, scan.scan.library_id) ?? '') : t('admin.tile.scanNever')
  );

  function subline(section: AdminSection): string | null {
    switch (section.id) {
      case 'libraries': {
        const env = data.libraries.filter((l) => l.managed === 'config').length;
        const parts = [countLabel('admin.librariesCount', data.libraries.length)];
        if (env > 0) parts.push(t('admin.index.envManaged', { count: env }));
        return parts.join(' · ');
      }
      case 'storage':
        return storage.unmounted.length > 0
          ? t('admin.tile.unmounted', { count: storage.unmounted.length })
          : countLabel('admin.roots', storage.rootCount);
      case 'activity': {
        const parts: string[] = [];
        if (scan?.active) parts.push(t('admin.state.running'));
        if (failedJobs > 0) parts.push(countLabel('admin.errors', failedJobs));
        return parts.length > 0 ? parts.join(' · ') : t('admin.tile.scanIdle');
      }
      case 'users':
        return countLabel('admin.users', data.users.length);
      default:
        return null;
    }
  }

  const groups = $derived([
    { key: 'manage', label: t('admin.index.manage'), sections: ADMIN_SECTIONS.filter((s) => s.group === 'manage') },
    { key: 'settings', label: t('admin.index.settings'), sections: ADMIN_SECTIONS.filter((s) => s.group === 'settings') }
  ]);
</script>

<h1 class="visually-hidden">{t('admin.title')}</h1>

{#if storage.unmounted.length > 0}
  <div class="alert">
    <Alert tone="warn" title={t('admin.alert.unmountedTitle')} live={false}>
      {#if storage.unmounted.length === 1}
        {t('admin.alert.unmountedBody', { path: storage.unmounted[0]!.path })}
      {:else}
        {t('admin.alert.unmountedMany', { count: storage.unmounted.length })}
      {/if}
    </Alert>
  </div>
{/if}

<dl class="mini">
  <div class="mini__tile">
    <dt>{t('admin.tile.scan')}</dt>
    <dd class="mini__v">{scanValue}</dd>
    <dd class="mini__s">{scanSub}</dd>
  </div>
  <div class="mini__tile">
    <dt>{t('admin.tile.storage')}</dt>
    <dd class="mini__v">{formatBytes(storage.free)}</dd>
    <dd class="mini__s">{t('admin.tile.free')}</dd>
  </div>
</dl>

{#each groups as group (group.key)}
  <h2 class="group-label">{group.label}</h2>
  <ul class="group">
    {#each group.sections as section (section.id)}
      {@const sub = subline(section)}
      <li>
        <a class="row" href={section.id === 'overview' ? ADMIN_OVERVIEW_PATH : section.href}>
          <AdminIcon name={section.icon} size={22} />
          <span class="body">
            <span class="t">{t(section.label)}</span>
            {#if sub}<span class="s">{sub}</span>{/if}
          </span>
          <span class="chev"><AdminIcon name="chev" size={18} /></span>
        </a>
      </li>
    {/each}
  </ul>
{/each}

<style>
  .alert {
    margin: 8px 0 14px;
  }

  .mini {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin: 0;
  }

  .mini__tile {
    min-width: 0;
    padding: 12px 14px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
    box-shadow: var(--ring-shadow);
  }

  dt {
    font-size: 13px;
    color: var(--ink-3);
  }

  dd {
    margin: 0;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .mini__v {
    margin-top: 6px;
    font-size: 20px;
    font-weight: 700;
    color: var(--ink);
    font-variant-numeric: tabular-nums;
  }

  .mini__s {
    margin-top: 2px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .group-label {
    margin: 22px 0 10px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--ink-3);
  }

  .group {
    margin: 0;
    padding: 0;
    list-style: none;
    overflow: hidden;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
  }

  li + li {
    border-top: 1px solid var(--hairline);
  }

  .row {
    display: flex;
    align-items: center;
    gap: 14px;
    min-height: 60px;
    padding: 12px 18px;
    color: var(--ink);
  }

  @media (hover: hover) {
    .row:hover {
      background: var(--row-hover);
    }
  }

  .body {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }

  .t,
  .s {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .t {
    font-size: 15px;
    font-weight: 500;
  }

  .s {
    margin-top: 2px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .chev {
    color: var(--ink-3);
  }
</style>
