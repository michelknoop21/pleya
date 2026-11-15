<!--
  De vier tellers onderaan het overzicht: bibliotheken, opslag, gebruikers en
  scan. Elke tegel is een link naar zijn sectie. Vier kolommen vanaf 1200,
  twee daaronder (web.css `.stats`). Een scanpercentage staat er niet: `Scan`
  draagt geen totaal, alleen wat er al gezien is. Het aantal kijkers staat
  niet meer hier maar in de kop van Nu aan het kijken.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import StatTile from '../components/StatTile.svelte';
  import { t } from '../i18n';
  import { formatBytes, formatCount, formatRelative } from '../util/format';
  import {
    countLabel,
    currentScan,
    libraryTitle,
    storageSummary,
    type OverviewData
  } from './overview';

  let { data }: { data: OverviewData } = $props();

  const libraries = $derived({
    value: formatCount(data.libraries.length),
    sub: data.libraries.map((l) => `${l.title} ${formatCount(l.item_count)}`).join(' · ')
  });

  const storage = $derived.by(() => {
    const s = storageSummary(data.roots);
    const parts = [
      t('admin.tile.storageOf', {
        total: formatBytes(s.total),
        roots: countLabel('admin.roots', s.rootCount)
      })
    ];
    if (s.unmounted.length > 0) {
      parts.push(t('admin.tile.unmounted', { count: s.unmounted.length }));
    }
    return { value: formatBytes(s.free), sub: parts.join(' · ') };
  });

  const scan = $derived.by(() => {
    const current = currentScan(data.scans);
    if (!current) return { value: t('admin.tile.scanIdle'), sub: t('admin.tile.scanNever') };
    const { scan: s, active } = current;
    const library = libraryTitle(data.libraries, s.library_id) ?? '';
    if (active) {
      return {
        value: t(s.state === 'queued' ? 'admin.state.queued' : 'admin.state.running'),
        sub: [library, countLabel('admin.files', s.files_seen)].filter(Boolean).join(' · ')
      };
    }
    const when = formatRelative(s.finished_at ?? s.started_at) ?? '';
    return {
      value: s.state === 'failed' ? t('admin.state.failed') : t('admin.tile.scanIdle'),
      sub: [library, when].filter(Boolean).join(' · ')
    };
  });

  const users = $derived({
    value: formatCount(data.users.length),
    sub: data.users.map((u) => u.username).join(' · ')
  });
</script>

<div class="tiles">
  <a class="tile" href="/admin/libraries">
    <StatTile label={t('admin.tile.libraries')} value={libraries.value} sub={libraries.sub}>
      {#snippet icon()}<AdminIcon name="folder" />{/snippet}
    </StatTile>
  </a>
  <a class="tile" href="/admin/storage">
    <StatTile
      label={t('admin.tile.storage')}
      value={storage.value}
      unit={t('admin.tile.free')}
      sub={storage.sub}
    >
      {#snippet icon()}<AdminIcon name="drive" />{/snippet}
    </StatTile>
  </a>
  <a class="tile" href="/admin/users">
    <StatTile label={t('admin.nav.users')} value={users.value} sub={users.sub}>
      {#snippet icon()}<AdminIcon name="people" />{/snippet}
    </StatTile>
  </a>
  <a class="tile" href="/admin/activity">
    <StatTile label={t('admin.tile.scan')} value={scan.value} sub={scan.sub}>
      {#snippet icon()}<AdminIcon name="activity" />{/snippet}
    </StatTile>
  </a>
</div>

<style>
  .tiles {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
  }

  /* De link is de hele tegel; de tegel zelf vult hem, zodat een rij even hoog blijft. */
  .tile {
    display: grid;
    min-width: 0;
    border-radius: var(--radius-panel);
    color: inherit;
    text-decoration: none;
  }

  @media (hover: hover) {
    .tile:hover :global(.stat) {
      border-color: var(--hairline-strong);
      background: var(--panel-2);
    }
  }

  @media (max-width: 1199px) {
    .tiles {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
</style>
