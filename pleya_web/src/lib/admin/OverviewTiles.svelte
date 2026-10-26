<!--
  De vier tellers van scherm 20: bibliotheken, opslag, scan en nu aan het
  kijken. Vier kolommen vanaf 1200, twee daaronder (web.css `.stats`).
  Een scanpercentage staat er niet: `Scan` draagt geen totaal, alleen wat er
  al gezien is.
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

  const watching = $derived({
    value: formatCount(data.streams.length),
    sub:
      data.streams.length === 0
        ? t('admin.tile.watchingNone')
        : data.streams.map((s) => s.device_name ?? s.username).join(' · ')
  });
</script>

<div class="tiles">
  <StatTile label={t('admin.tile.libraries')} value={libraries.value} sub={libraries.sub}>
    {#snippet icon()}<AdminIcon name="folder" />{/snippet}
  </StatTile>
  <StatTile
    label={t('admin.tile.storage')}
    value={storage.value}
    unit={t('admin.tile.free')}
    sub={storage.sub}
  >
    {#snippet icon()}<AdminIcon name="drive" />{/snippet}
  </StatTile>
  <StatTile label={t('admin.tile.scan')} value={scan.value} sub={scan.sub}>
    {#snippet icon()}<AdminIcon name="activity" />{/snippet}
  </StatTile>
  <StatTile label={t('admin.tile.watching')} value={watching.value} sub={watching.sub}>
    {#snippet icon()}<AdminIcon name="play" />{/snippet}
  </StatTile>
</div>

<style>
  .tiles {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
  }

  @media (max-width: 1199px) {
    .tiles {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
</style>
