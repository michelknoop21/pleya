<!--
  Sidecars (.nfo) per bibliotheek (29, links): de dekking van genres als balk
  met de poort (de drempel komt van de server, niet van deze client), en de
  aantallen titels met sidecar, samenvatting en genres. De balk volgt de
  verhouding waar de poort op rekent; de northstar tekent het aandeel
  sidecars, maar dat is niet waar een genrefilter van afhangt.
-->
<script lang="ts">
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import { formatCount } from '../../util/format';
  import { formatPercent, gateLabel, percent, type CoverageRow } from './metadata';

  let { rows, threshold }: { rows: CoverageRow[]; threshold: number | null } = $props();

  const columns: Column[] = [
    { key: 'library', label: t('admin.meta.col.library') },
    { key: 'coverage', label: t('admin.meta.col.coverage') },
    { key: 'sidecar', label: t('admin.meta.col.sidecar'), showLabel: true },
    { key: 'summary', label: t('admin.meta.col.summary'), showLabel: true },
    { key: 'genres', label: t('admin.meta.col.genres'), showLabel: true },
    { key: 'gate', label: t('admin.meta.col.gate'), align: 'end' }
  ];
</script>

<DataTable
  {columns}
  {rows}
  label={t('admin.meta.sidecars.title')}
  rowKey={(row) => row.library.id}
  rowData={(row) => ({ 'data-library': row.library.id })}
  stack
>
  {#snippet title()}{t('admin.meta.sidecars.title')}{/snippet}
  {#snippet empty()}{t('admin.meta.empty')}{/snippet}
  {#snippet cell(row, column)}
    {@const c = row.coverage}
    {#if column.key === 'library'}
      {row.library.title}
    {:else if !c}
      {#if column.key === 'coverage'}<span class="muted">{t('admin.meta.unreadable')}</span>{/if}
    {:else if column.key === 'coverage'}
      <div
        class="bar"
        role="meter"
        aria-label={t('admin.meta.coverage.label', { title: row.library.title })}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent(c.ratio)}
      >
        <span class="fill" class:fill--low={!c.gate_met} style:width="{percent(c.ratio)}%"></span>
      </div>
      <span class="note"
        >{t('admin.meta.coverage.text', {
          percent: formatPercent(percent(c.ratio)),
          genres: formatCount(c.with_genres),
          items: formatCount(c.items)
        })}</span
      >
    {:else if column.key === 'sidecar'}
      {formatCount(c.with_sidecar)}
    {:else if column.key === 'summary'}
      {formatCount(c.with_summary)}
    {:else if column.key === 'genres'}
      {formatCount(c.with_genres)}
    {:else if column.key === 'gate'}
      {@const gate = gateLabel(c)}
      <StatusPill size="sm" tone={gate.tone} label={gate.label} />
    {/if}
  {/snippet}
  {#snippet footer()}
    <p class="foot">
      {threshold === null
        ? t('admin.meta.sidecars.footPlain')
        : t('admin.meta.sidecars.foot', { percent: formatPercent(percent(threshold)) })}
    </p>
  {/snippet}
</DataTable>

<style>
  .bar {
    width: 100%;
    min-width: 110px;
    height: 4px;
    overflow: hidden;
    border-radius: 2px;
    background: var(--fill-2);
  }

  .fill {
    display: block;
    height: 100%;
    background: var(--ink);
  }

  .fill--low {
    background: var(--amber-graphic);
  }

  .note {
    display: block;
    margin-top: 5px;
    font-size: 12px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .muted {
    color: var(--ink-3);
  }

  .foot {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
