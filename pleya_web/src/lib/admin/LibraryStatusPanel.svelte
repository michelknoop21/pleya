<!--
  Het paneel Stand van scherm 22: titels, de laatste scan en, als de server de
  dekking kent, het aandeel titels met een sidecar.

  De northstar zet er versies, opslaggrootte en onanalyseerbare bestanden bij.
  Die levert het contract niet per bibliotheek, dus die regels staan er niet.
-->
<script lang="ts">
  import Panel from '../components/Panel.svelte';
  import type { Library, MetadataCoverage, Scan } from '../api/types';
  import { t } from '../i18n';
  import { formatCount, formatDuration, formatRelative } from '../util/format';
  import { countLabel } from './overview';
  import { scanActive, scanSummary } from './libraries';

  interface Props {
    library: Library;
    scan: Scan | null;
    coverage: MetadataCoverage | null;
  }

  let { library, scan, coverage }: Props = $props();

  const scanText = $derived.by(() => {
    if (!scan || scanActive(scan) || scan.state !== 'done') return scanSummary(scan).text;
    const parts = [formatRelative(scan.finished_at ?? scan.started_at) ?? ''];
    const took = scan.finished_at
      ? formatDuration(Date.parse(scan.finished_at) - Date.parse(scan.started_at))
      : null;
    if (took) parts.push(took);
    parts.push(
      t('admin.lib.status.scanCounts', {
        added: formatCount(scan.items_created),
        missing: formatCount(scan.files_missing)
      })
    );
    return parts.filter(Boolean).join(' · ');
  });

  const sidecarShare = $derived(
    coverage && coverage.items > 0 ? Math.round((coverage.with_sidecar / coverage.items) * 100) : null
  );
</script>

<Panel>
  {#snippet title()}{t('admin.lib.status.title')}{/snippet}
  <dl class="kv">
    <dt>{t('admin.lib.status.titles')}</dt>
    <dd>{countLabel('admin.lib.titles', library.item_count)}</dd>
    <dt>{t('admin.lib.status.lastScan')}</dt>
    <dd>{scanText}</dd>
    {#if sidecarShare !== null}
      <dt>{t('admin.lib.status.sidecars')}</dt>
      <dd>{t('admin.lib.status.sidecarShare', { percent: sidecarShare })}</dd>
    {/if}
  </dl>
</Panel>

<style>
  .kv {
    display: grid;
    grid-template-columns: 120px minmax(0, 1fr);
    gap: 8px 16px;
    margin: 0;
    font-size: 14px;
    line-height: 1.4;
  }

  dt {
    color: var(--ink-3);
  }

  dd {
    margin: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
  }
</style>
