<!--
  De tabel van scherm 21: bibliotheek, soort, opslag, inhoud, laatste scan en
  de acties per rij. Onder 900 stapelt hij (DataTable `stack`): een rij met
  knoppen hoort niet half buiten beeld te scrollen.

  Wat het contract niet draagt laat hij weg: geen slug, geen aantal versies of
  afleveringen naast de titels, geen scanpercentage, en geen knop Afbreken,
  want een scan heeft geen eigen afbreekroute (zie het PR-verslag van S10.2).
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import DataTable, { type Column } from '../components/DataTable.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import type { Library } from '../api/types';
  import { t } from '../i18n';
  import { countLabel } from './overview';
  import {
    isConfigManaged,
    kindLabel,
    rootsOf,
    scanActive,
    scanSummary,
    type LibrariesData
  } from './libraries';

  interface Props {
    data: LibrariesData;
    /** Bibliotheken waarvoor nu een scanaanvraag loopt. */
    starting: Record<string, boolean>;
    onscan: (library: Library) => void;
    onadopt: (library: Library) => void;
  }

  let { data, starting, onscan, onadopt }: Props = $props();

  const columns: Column[] = [
    { key: 'title', label: t('admin.lib.col.library') },
    { key: 'kind', label: t('admin.lib.col.kind') },
    { key: 'roots', label: t('admin.lib.col.storage') },
    { key: 'items', label: t('admin.lib.col.content') },
    { key: 'scan', label: t('admin.lib.col.scan') },
    { key: 'actions', label: t('admin.lib.col.actions'), align: 'end', hideLabel: true }
  ];
</script>

<div class="libs">
  <DataTable
    {columns}
    rows={data.libraries}
    label={t('admin.nav.libraries')}
    rowKey={(row) => row.id}
    rowData={(row) => ({ 'data-library': row.id })}
    stack
  >
    {#snippet cell(library, column)}
      {@const roots = rootsOf(data.roots, library.id)}
      {@const scan = data.scans[library.id] ?? null}
      {#if column.key === 'title'}
        <a class="name" href={`/admin/libraries/${library.id}`}>{library.title}</a>
        {#if isConfigManaged(library)}
          <span class="env"><StatusPill size="sm" tone="warn" label={t('admin.lib.managedEnv')} /></span>
        {/if}
      {:else if column.key === 'kind'}
        {kindLabel(library.kind)}
      {:else if column.key === 'roots'}
        {#if roots.length === 0}
          <span class="muted">{t('admin.lib.noRoots')}</span>
        {:else}
          <ul class="roots">
            {#each roots as root (root.path)}
              <li>
                <span class="mono path">{root.path}</span>
                {#if !root.mounted}
                  <StatusPill size="sm" tone="err" label={t('admin.lib.root.unmounted')} />
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {:else if column.key === 'items'}
        {countLabel('admin.lib.titles', library.item_count)}
      {:else if column.key === 'scan'}
        {@const summary = scanSummary(scan)}
        <StatusPill variant="dot" tone={summary.tone} label={summary.text} />
      {:else if column.key === 'actions'}
        <div class="acts">
          {#if roots.some((r) => !r.mounted)}
            <a class="btn btn--ghost btn--sm" href="/admin/storage">
              <AdminIcon name="drive" size={16} />{t('admin.nav.storage')}
            </a>
          {:else}
            <button
              type="button"
              class="btn btn--ghost btn--sm"
              disabled={scanActive(scan) || starting[library.id]}
              aria-label={t('admin.lib.action.scanNamed', { name: library.title })}
              onclick={() => onscan(library)}
            >
              <AdminIcon name="scan" size={16} />{t('admin.lib.action.scan')}
            </button>
          {/if}
          {#if isConfigManaged(library)}
            <button type="button" class="btn btn--ghost btn--sm" onclick={() => onadopt(library)}>
              {t('admin.lib.action.adopt')}
            </button>
          {:else}
            <a
              class="btn btn--ghost btn--sm btn--icon"
              href={`/admin/libraries/${library.id}`}
              aria-label={t('admin.lib.action.editNamed', { name: library.title })}
            >
              <AdminIcon name="edit" size={16} />
            </a>
          {/if}
        </div>
      {/if}
    {/snippet}
  </DataTable>
</div>

<style>
  .name {
    font-weight: 600;
    color: var(--ink);
  }

  @media (hover: hover) {
    .name:hover {
      text-decoration: underline;
    }
  }

  .env {
    display: block;
    margin-top: 4px;
  }

  .muted {
    color: var(--ink-3);
  }

  .roots {
    display: grid;
    gap: 2px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .roots li {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
  }

  .path {
    color: var(--ink-2);
    overflow-wrap: anywhere;
  }

  .acts {
    display: inline-flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }

  .acts :global(.btn--icon) {
    width: 36px;
  }

  /* Gestapeld krijgen de knoppen een eigen regel onder de kaart: naast de
     tekst passen Scannen en Overnemen in beheer op 320 niet. */
  @media (max-width: 899px) {
    .libs :global(.tbl--stack td.tbl__end) {
      grid-column: 1 / -1;
      grid-row: auto;
      margin-top: 8px;
    }

    .acts {
      justify-content: flex-start;
    }
  }
</style>
