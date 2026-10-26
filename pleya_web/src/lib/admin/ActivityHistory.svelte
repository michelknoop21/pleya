<!--
  De Geschiedenis van scherm 25: de scans, nieuwste eerst, in de tabel van de
  andere beheerschermen. Het resultaat zijn de tellers van de server; een scan
  die faalde toont zijn laatste foutmelding. "Overgeslagen" en "afgebroken door
  Michel bij 31%" uit de northstar bestaan niet: het contract kent geen
  overgeslagen scan, geen afbreker en geen percentage.
-->
<script lang="ts">
  import DataTable, { type Column } from '../components/DataTable.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { t } from '../i18n';
  import type { HistoryRow } from './activity';

  interface Props {
    rows: HistoryRow[];
    more: boolean;
    loadingMore: boolean;
    onmore: () => void;
  }

  let { rows, more, loadingMore, onmore }: Props = $props();

  const columns: Column[] = [
    { key: 'title', label: t('admin.act.col.task') },
    { key: 'started', label: t('admin.act.col.started') },
    { key: 'duration', label: t('admin.act.col.duration') },
    { key: 'result', label: t('admin.act.col.result') },
    { key: 'state', label: t('admin.act.col.status'), align: 'end' }
  ];
</script>

<DataTable
  {columns}
  {rows}
  label={t('admin.act.history.title')}
  rowKey={(row) => row.id}
  rowData={(row) => ({ 'data-scan': row.id })}
  stack
>
  {#snippet title()}{t('admin.act.history.title')}{/snippet}
  {#snippet empty()}{t('admin.act.history.empty')}{/snippet}
  {#snippet cell(row, column)}
    {#if column.key === 'title'}
      <span class="name">{row.title}</span>
      <span class="sub">{row.trigger}</span>
    {:else if column.key === 'started'}
      {row.started}
    {:else if column.key === 'duration'}
      {row.duration}
    {:else if column.key === 'result'}
      {row.result}
    {:else if column.key === 'state'}
      <StatusPill size="sm" tone={row.tone} label={row.state} />
    {/if}
  {/snippet}
</DataTable>
{#if more}
  <div class="more">
    <button type="button" class="btn btn--secondary btn--sm" disabled={loadingMore} onclick={onmore}>
      {loadingMore ? t('admin.act.history.moreBusy') : t('admin.act.history.more')}
    </button>
  </div>
{/if}

<style>
  .name {
    font-weight: 500;
    color: var(--ink);
  }

  .sub {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .more {
    display: flex;
    justify-content: center;
    margin-top: 12px;
  }
</style>
