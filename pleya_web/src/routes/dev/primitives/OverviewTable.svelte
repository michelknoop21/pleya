<!--
  De bibliotheektabel van specimen v2: naam met slug in mono en een tag,
  pad in mono, statuscel als stip plus tekst (met voortgang tijdens een scan)
  en een actie per rij. Met een actie per rij stapelt hij onder 900 (`stack`).
  Gallerijlabels zijn gewone Nederlandse tekst: de route bestaat alleen in
  ontwikkeling.
-->
<script lang="ts">
  import DataTable, { type Column } from '$lib/components/DataTable.svelte';
  import StatusPill from '$lib/components/StatusPill.svelte';
  import { LIBRARY_ROWS, type LibraryRow } from './overviewData';

  const columns: Column[] = [
    { key: 'name', label: 'Naam' },
    { key: 'path', label: 'Opslag', mono: true },
    { key: 'items', label: 'Inhoud' },
    { key: 'scan', label: 'Laatste scan' },
    { key: 'action', label: 'Acties', align: 'end', hideLabel: true }
  ];
</script>

{#snippet cell(row: LibraryRow, column: Column)}
  {#if column.key === 'name'}
    <span class="ot__name">
      {row.name}
      {#if row.tag}<StatusPill tone={row.tag.tone} label={row.tag.label} size="sm" />{/if}
    </span>
    <span class="ot__slug mono">{row.slug}</span>
  {:else if column.key === 'path'}
    {row.path}
  {:else if column.key === 'items'}
    {row.items}
  {:else if column.key === 'scan'}
    <StatusPill variant="dot" tone={row.scan.tone} label={row.scan.label} />
    {#if row.scan.progress !== undefined}
      <!-- Voortgang is versiering naast "bezig"; het percentage staat in de Scan-tegel. -->
      <span class="ot__bar" aria-hidden="true"><i style:width="{row.scan.progress}%"></i></span>
    {/if}
  {:else}
    <button type="button" class="btn btn--ghost btn--sm">{row.action}</button>
  {/if}
{/snippet}

<DataTable label="Bibliotheken" {columns} rows={LIBRARY_ROWS} rowKey={(r) => r.slug} {cell} stack>
  {#snippet title()}Bibliotheken{/snippet}
  {#snippet actions()}
    <button type="button" class="btn btn--sm">+ Toevoegen</button>
  {/snippet}
</DataTable>

<style>
  .ot__name {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 8px;
    font-weight: 600;
    color: var(--ink);
  }

  .ot__slug {
    display: block;
    margin-top: 3px;
    font-size: 12px;
    /* Gestapeld wordt de eerste cel een vette titel; de slug hoort daar niet bij. */
    font-weight: 400;
    color: var(--ink-3);
  }

  .ot__bar {
    display: block;
    width: 120px;
    height: 6px;
    margin-top: 7px;
    overflow: hidden;
    border-radius: 3px;
    background: var(--fill-2);
  }

  .ot__bar i {
    display: block;
    height: 100%;
    border-radius: 3px;
    background: var(--amber-graphic);
  }
</style>
