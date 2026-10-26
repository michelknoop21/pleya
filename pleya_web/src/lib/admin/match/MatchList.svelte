<!--
  De titels die op een keuze wachten (36, links boven) als tabel, gestapeld
  onder 900: titel met de reden eronder, soort, uitkomst en wanneer de server
  de titel voor het laatst aanraakte. De titel is een knop die de titel
  selecteert; deze lijst stuurt zelf niets naar de server.
-->
<script lang="ts">
  import type { MetadataAttention, MetadataAttentionList } from '../../api/types';
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import { formatRelative } from '../../util/format';
  import { hintLabel, kindLabel, outcomeLabel, outcomeTone, titleOf } from './match';

  interface Props {
    list: MetadataAttentionList;
    items: MetadataAttention[];
    selected: string | null;
    onselect: (id: string) => void;
  }

  let { list, items, selected, onselect }: Props = $props();

  const columns: Column[] = [
    { key: 'title', label: t('admin.match.col.title') },
    { key: 'kind', label: t('admin.match.col.kind'), showLabel: true },
    { key: 'outcome', label: t('admin.match.col.outcome') },
    { key: 'updated', label: t('admin.match.col.updated'), showLabel: true }
  ];
</script>

<DataTable
  {columns}
  rows={items}
  label={t('admin.match.list.title')}
  rowKey={(row) => row.item_id}
  rowData={(row) => ({ 'data-item': row.item_id })}
  stack
>
  {#snippet title()}{t('admin.match.list.title')}{/snippet}
  {#snippet actions()}
    <span class="count">{plural('admin.meta.attention.total', list.total)}</span>
  {/snippet}
  {#snippet empty()}{t('admin.meta.attention.none')}{/snippet}
  {#snippet cell(item, column)}
    {#if column.key === 'title'}
      <button
        type="button"
        class="pick"
        aria-pressed={item.item_id === selected}
        aria-label={t('admin.match.select', { title: titleOf(item) })}
        onclick={() => onselect(item.item_id)}
      >
        {titleOf(item)}
      </button>
      <span class="hint">{hintLabel(item.state)}</span>
    {:else if column.key === 'kind'}
      {kindLabel(item.kind)}
    {:else if column.key === 'outcome'}
      <StatusPill size="sm" tone={outcomeTone(item)} label={outcomeLabel(item)} />
    {:else if column.key === 'updated'}
      {formatRelative(item.updated_at) ?? ''}
    {/if}
  {/snippet}
  {#snippet footer()}
    {#if list.total > list.items.length}
      <p class="foot">
        {t('admin.match.list.truncated', { shown: list.items.length, total: list.total })}
      </p>
    {/if}
  {/snippet}
</DataTable>

<style>
  .count {
    font-size: 13px;
    color: var(--ink-3);
  }

  .pick {
    display: block;
    max-width: 100%;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink);
    font: inherit;
    font-weight: 600;
    text-align: start;
    cursor: pointer;
    overflow-wrap: anywhere;
  }

  .pick[aria-pressed='true'] {
    text-decoration: underline;
    text-underline-offset: 4px;
  }

  .hint {
    display: block;
    font-weight: 400;
    margin-top: 2px;
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .foot {
    margin: 0;
    font-size: 12.5px;
    color: var(--ink-3);
  }
</style>
