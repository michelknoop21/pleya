<!--
  De tabel van scherm 26: gebruiker, rol, bibliotheken, laatst actief,
  toestellen en een potlood per rij. Onder 900 stapelt hij (DataTable `stack`),
  zoals de bibliotheken: een actie per rij hoort niet buiten beeld te staan.

  Niet gebouwd omdat het contract het niet draagt: "aangemaakt op" (een `User`
  heeft geen datum) en de namen van de bibliotheken van een lid (de rechten
  zijn alleen te schrijven, niet te lezen).
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import DataTable, { type Column } from '../components/DataTable.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import {
    deviceSessions,
    lastActiveText,
    librariesText,
    roleLabel,
    roleTone,
    type UserEntry
  } from './users';

  let { entries }: { entries: UserEntry[] } = $props();

  const columns: Column[] = [
    { key: 'user', label: t('admin.users.col.user') },
    { key: 'role', label: t('admin.users.col.role') },
    { key: 'libraries', label: t('admin.users.col.libraries') },
    { key: 'active', label: t('admin.users.col.lastActive') },
    { key: 'devices', label: t('admin.users.col.devices'), showLabel: true },
    { key: 'actions', label: t('admin.users.col.actions'), align: 'end', hideLabel: true }
  ];
</script>

<DataTable
  {columns}
  rows={entries}
  label={t('admin.nav.users')}
  rowKey={(row) => row.user.id}
  rowData={(row) => ({ 'data-user': row.user.id })}
  stack
>
  {#snippet cell(entry, column)}
    {#if column.key === 'user'}
      <a class="name" href={`/admin/users/${entry.user.id}`}>{entry.user.username}</a>
      {#if session.me?.id === entry.user.id}
        <span class="you"><StatusPill size="sm" label={t('admin.users.you')} /></span>
      {/if}
    {:else if column.key === 'role'}
      <StatusPill size="sm" tone={roleTone(entry.user.role)} label={roleLabel(entry.user.role)} />
    {:else if column.key === 'libraries'}
      {librariesText(entry.user.role)}
    {:else if column.key === 'active'}
      {lastActiveText(entry.sessions)}
    {:else if column.key === 'devices'}
      {entry.sessions === null ? t('admin.users.lastActive.unknown') : deviceSessions(entry.sessions).length}
    {:else if column.key === 'actions'}
      <a
        class="btn btn--ghost btn--sm btn--icon"
        href={`/admin/users/${entry.user.id}`}
        aria-label={t('admin.users.action.editNamed', { name: entry.user.username })}
      >
        <AdminIcon name="edit" size={16} />
      </a>
    {/if}
  {/snippet}
</DataTable>

<style>
  .name {
    font-weight: 600;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .you {
    margin-left: 8px;
  }
</style>
