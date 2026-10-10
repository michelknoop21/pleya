<!-- Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen in ontwikkeling. -->
<script lang="ts">
  import DataTable, { type Column } from '$lib/components/DataTable.svelte';
  import Steps from '$lib/components/Steps.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import StatusPill from '$lib/components/StatusPill.svelte';
  import GallerySection from './GallerySection.svelte';

  interface Row {
    name: string;
    kind: string;
    path: string;
    items: string;
    status: string;
  }

  const columns: Column[] = [
    { key: 'name', label: 'Naam' },
    { key: 'kind', label: 'Soort' },
    { key: 'path', label: 'Pad', mono: true },
    { key: 'items', label: 'Titels', align: 'end' },
    { key: 'status', label: 'Laatste scan' }
  ];

  const stackColumns: Column[] = [
    { key: 'name', label: 'Naam' },
    { key: 'kind', label: 'Soort' },
    { key: 'path', label: 'Pad', mono: true },
    // Een kaal getal zegt gestapeld niets; deze kolom toont zijn naam wel.
    { key: 'items', label: 'Titels', showLabel: true },
    { key: 'status', label: 'Acties', align: 'end', hideLabel: true }
  ];

  const rows: Row[] = [
    { name: 'Films', kind: 'Films', path: '/volume1/media/films', items: '1.024', status: 'ok' },
    { name: 'Series', kind: 'Series', path: '/volume1/media/series', items: '212', status: 'run' },
    { name: 'Kinderen', kind: 'Films', path: '/volume1/media/kids', items: '48', status: 'err' }
  ];

  const setup = ['Eigenaar', 'Opslag', 'Bibliotheek', 'Scan', 'Klaar'];

  let plainOpen = $state(false);
  let phraseOpen = $state(false);
</script>

{#snippet statusCell(row: Row, column: Column)}
  {#if column.key === 'status'}
    <StatusPill
      variant="dot"
      tone={row.status === 'ok' ? 'ok' : row.status === 'run' ? 'run' : 'err'}
      label={row.status === 'ok' ? 'vandaag 08:12' : row.status === 'run' ? 'bezig' : 'overgeslagen 07:12'}
    />
  {:else}
    {row[column.key as keyof Row]}
  {/if}
{/snippet}

{#snippet actionCell(row: Row, column: Column)}
  {#if column.key === 'status'}
    <button type="button" class="btn btn--ghost btn--sm">Bewerken</button>
  {:else}
    {row[column.key as keyof Row]}
  {/if}
{/snippet}

<GallerySection id="tabel" title="Tabel">
  <DataTable label="Bibliotheken, scrollend" {columns} {rows} cell={statusCell}>
    {#snippet title()}Bibliotheken{/snippet}
    {#snippet actions()}
      <button type="button" class="btn btn--secondary btn--sm">Toevoegen</button>
    {/snippet}
  </DataTable>
  <DataTable label="Bibliotheken, gestapeld" columns={stackColumns} {rows} cell={actionCell} stack>
    {#snippet title()}Gestapeld onder 900{/snippet}
  </DataTable>
  <DataTable label="Lege tabel" {columns} rows={[]}>
    {#snippet title()}Leeg{/snippet}
  </DataTable>
</GallerySection>

<GallerySection id="stappen" title="Stappen">
  <Steps steps={setup} current={0} />
  <Steps steps={setup} current={2} />
  <Steps steps={setup} current={4} />
  <Steps steps={setup} current={5} />
</GallerySection>

<GallerySection id="dialoog" title="Bevestigdialoog">
  <div class="gs__row">
    <button type="button" class="btn btn--secondary" data-open="plain" onclick={() => (plainOpen = true)}>
      Gewone bevestiging
    </button>
    <button type="button" class="btn btn--danger" data-open="phrase" onclick={() => (phraseOpen = true)}>
      Met overtypzin
    </button>
  </div>
</GallerySection>

<ConfirmDialog
  bind:open={plainOpen}
  title="Scan stoppen?"
  message="De scan van Films stopt nu. Wat al gevonden is, blijft staan."
  confirmLabel="Stoppen"
  danger={false}
  onconfirm={() => (plainOpen = false)}
/>

<ConfirmDialog
  bind:open={phraseOpen}
  title="Bibliotheek Films verwijderen?"
  message="Dit haalt de bibliotheek en alle kijkstatus weg. De bestanden op schijf blijven staan."
  confirmLabel="Verwijderen"
  requirePhrase="Films"
  onconfirm={() => (phraseOpen = false)}
>
  <ul class="t-body">
    <li>1.024 titels verdwijnen uit Pleya</li>
    <li>Kijkpositie van 3 gebruikers gaat verloren</li>
  </ul>
  {#snippet confirmIcon()}
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
      <path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12" fill="none" stroke="currentColor" stroke-width="1.8" />
    </svg>
  {/snippet}
</ConfirmDialog>
