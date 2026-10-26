<!--
  De tabel van scherm 24: root, bestandssysteem, inode, ruimte, bibliotheken en
  status. Een root draagt zijn pad in monoletter met eronder "niet in gebruik"
  of "scan bezig". Onder 900 stapelt hij (DataTable `stack`), zoals de
  bibliotheektabel; de northstar laat de overige kolommen op 393 buiten beeld
  scrollen, en dat is voor een ruimtebalk geen goede uitweg.

  Niet getoond omdat het contract het niet draagt: wanneer een root voor het
  laatst gezien werd (de northstar tekent "gezien 14:31").
-->
<script lang="ts">
  import DataTable, { type Column } from '../components/DataTable.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import type { StorageRoot } from '../api/types';
  import { t } from '../i18n';
  import RootSpace from './RootSpace.svelte';
  import { rootNotes, rootSpace, rootTrust } from './storage';

  interface Props {
    roots: StorageRoot[];
    scanning: Set<string>;
  }

  let { roots, scanning }: Props = $props();

  const columns: Column[] = [
    { key: 'root', label: t('admin.sto.col.root') },
    { key: 'fs', label: t('admin.sto.col.fs') },
    { key: 'inode', label: t('admin.sto.col.inode') },
    { key: 'space', label: t('admin.sto.col.space') },
    { key: 'libraries', label: t('admin.sto.col.libraries') },
    { key: 'status', label: t('admin.sto.col.status'), align: 'end' }
  ];
</script>

<DataTable
  {columns}
  rows={roots}
  label={t('admin.nav.storage')}
  rowKey={(row) => row.path}
  rowData={(row) => ({ 'data-root': row.path })}
  stack
>
  {#snippet empty()}{t('admin.sto.empty')}{/snippet}
  {#snippet cell(root, column)}
    {#if column.key === 'root'}
      <!-- Breken mag alleen na een schuine streep, nooit midden in een mapnaam. -->
      <span class="mono path"
        >{#each root.path.split('/') as part, i (i)}{#if i > 0}/<wbr />{/if}{part}{/each}</span
      >
      {#each rootNotes(root, scanning) as note (note)}
        <span class="note">{note}</span>
      {/each}
    {:else if column.key === 'fs'}
      {#if root.fs_type}{root.fs_type}{:else}<span class="muted">{t('admin.sto.fs.unknown')}</span>{/if}
    {:else if column.key === 'inode'}
      {@const trust = rootTrust(root)}
      <StatusPill size="sm" tone={trust.tone} label={trust.label} />
      <span class="note">{trust.detail}</span>
    {:else if column.key === 'space'}
      <RootSpace space={rootSpace(root)} />
    {:else if column.key === 'libraries'}
      {#if root.libraries.length === 0}
        <span class="muted">{t('admin.sto.libs.none')}</span>
      {:else}
        {root.libraries.map((l) => l.title).join(', ')}
      {/if}
    {:else if column.key === 'status'}
      <StatusPill
        variant="dot"
        tone={root.mounted ? 'ok' : 'err'}
        label={root.mounted ? t('admin.lib.root.mounted') : t('admin.lib.root.unmounted')}
      />
    {/if}
  {/snippet}
</DataTable>

<style>
  /* Vanaf 1400 houdt een pad zich op één regel, zoals de northstar; smaller
     breekt hij, anders schuift de statuskolom het paneel uit. */
  .path {
    overflow-wrap: break-word;
  }

  @media (min-width: 1400px) {
    .path {
      white-space: nowrap;
    }
  }

  .note {
    display: block;
    margin-top: 3px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .muted {
    color: var(--ink-3);
  }
</style>
