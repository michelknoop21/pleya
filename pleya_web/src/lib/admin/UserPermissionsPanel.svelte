<!--
  Het paneel Bibliotheken van scherm 27: per bibliotheek drie vinkjes
  (kijken, downloaden, beheren) volgens de ladder uit DEC-119. Een bibliotheek
  zonder vinkje bestaat voor de gebruiker niet.

  Het contract heeft geen leesroute voor de rechten die een gebruiker nu heeft.
  Het paneel begint daarom leeg en zegt dat. Pas na een eerste vinkje (of
  een weggehaald vinkje) telt het als aangeraakt, en alleen dan schrijft
  Opslaan (na een bevestiging) de hele lijst. Een eigenaar of beheerder heeft
  geen rechtenrijen: zijn toegang volgt uit de rol, dus het paneel toont dan
  alleen die uitleg. Een beperkte gebruiker kan geen vinkje bij Beheren zetten.
-->
<script lang="ts">
  import type { Library, Role } from '../api/types';
  import Alert from '../components/Alert.svelte';
  import DataTable, { type Column } from '../components/DataTable.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import GrantCheckbox from './GrantCheckbox.svelte';
  import {
    RUNGS,
    isGranted,
    rungLabel,
    seesEverything,
    toggleGrant,
    type Grants,
    type Rung
  } from './users';

  interface Props {
    name: string;
    role: Role;
    libraries: Library[];
    grants: Grants;
    /** Of de beheerder de matrix aangeraakt heeft; alleen dan wordt er geschreven. */
    touched: boolean;
    /** Of de matrix de lijst toont die de server na een schrijfactie teruggaf. */
    confirmedByServer: boolean;
  }

  let {
    name,
    role,
    libraries,
    grants = $bindable(),
    touched = $bindable(),
    confirmedByServer
  }: Props = $props();

  const columns: Column[] = $derived([
    { key: 'library', label: t('admin.users.perm.library') },
    ...RUNGS.map((r) => ({ key: r, label: rungLabel(r) }))
  ]);

  function change(libraryId: string, rung: Rung, checked: boolean): void {
    grants = toggleGrant(grants, libraryId, rung, checked);
    touched = true;
  }
</script>

{#if seesEverything(role)}
  <Panel>
    {#snippet title()}{t('admin.users.perm.title')}{/snippet}
    <p class="note">{t('admin.users.perm.byRole', { name })}</p>
  </Panel>
{:else}
  <div class="perm">
    {#if !confirmedByServer && !touched}
      <Alert tone="info" live={false}>{t('admin.users.perm.unreadable', { name })}</Alert>
    {:else if confirmedByServer && !touched}
      <Alert tone="info" live={false}>{t('admin.users.perm.confirmed', { name })}</Alert>
    {/if}
    <DataTable
      {columns}
      rows={libraries}
      label={t('admin.users.perm.title')}
      rowKey={(row) => row.id}
      rowData={(row) => ({ 'data-library': row.id })}
    >
      {#snippet title()}{t('admin.users.perm.title')}{/snippet}
      {#snippet empty()}{t('admin.users.perm.noLibraries')}{/snippet}
      {#snippet cell(library, column)}
        {#if column.key === 'library'}
          {library.title}
        {:else}
          {@const rung = column.key as Rung}
          <GrantCheckbox
            label={`${library.title}, ${rungLabel(rung)}`}
            checked={isGranted(grants, library.id, rung)}
            disabled={rung === 'manage' && role === 'restricted'}
            onchange={(checked) => change(library.id, rung, checked)}
          />
        {/if}
      {/snippet}
      {#snippet footer()}
        <p class="note">
          {t('admin.users.perm.footnote', { name })}
          {#if role === 'restricted'}{t('admin.users.perm.noManage')}{/if}
        </p>
      {/snippet}
    </DataTable>
  </div>
{/if}

<style>
  .perm {
    display: grid;
    gap: 12px;
  }

  .note {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
