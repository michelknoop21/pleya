<!--
  De lopende sessies van scherm 37 als tabel (gestapeld onder 900): gebruiker,
  omzetting met de hardware, wanneer hij begon en de laatste hartslag, en
  Stoppen per sessie. Stoppen vraagt de bevestiging van de pagina; deze tabel
  stuurt zelf niets.
-->
<script lang="ts">
  import AdminIcon from '../../components/AdminIcon.svelte';
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import type { TranscodeSession, User } from '../../api/types';
  import { t } from '../../i18n';
  import { formatRelative } from '../../util/format';
  import { modeLabel, userName } from '../settings/media';
  import { shortId } from './transcode';

  interface Props {
    items: TranscodeSession[];
    users: User[] | null;
    /** Sessies waarvoor nu een stopaanvraag loopt. */
    stopping: Record<string, boolean>;
    onstop: (id: string, name: string) => void;
  }

  let { items, users, stopping, onstop }: Props = $props();

  const columns: Column[] = [
    { key: 'user', label: t('admin.tc.col.user') },
    { key: 'mode', label: t('admin.tc.col.mode') },
    { key: 'started', label: t('admin.tc.col.started'), showLabel: true },
    { key: 'heartbeat', label: t('admin.tc.col.heartbeat'), showLabel: true },
    { key: 'actions', label: t('admin.tc.col.actions'), align: 'end', hideLabel: true }
  ];
</script>

<DataTable
  {columns}
  rows={items}
  label={t('admin.tc.running.title')}
  rowKey={(row) => row.id}
  rowData={(row) => ({ 'data-session': row.id })}
  stack
>
  {#snippet title()}{t('admin.tc.running.title')}{/snippet}
  {#snippet empty()}{t('admin.tc.running.empty')}{/snippet}
  {#snippet cell(item, column)}
    {@const name = userName(users, item.user_id)}
    {#if column.key === 'user'}
      <span class="who">{name}</span>
      <span class="note mono">{t('admin.tc.version', { id: shortId(item.version_id) })}</span>
    {:else if column.key === 'mode'}
      {modeLabel(item.mode)}
      <span class="hw">
        {#if item.hw_accel}
          <StatusPill size="sm" tone="ok" label={item.hw_accel.toUpperCase()} />
        {:else}
          <StatusPill size="sm" tone="idle" label={t('admin.media.transcode.software')} />
        {/if}
      </span>
    {:else if column.key === 'started'}
      {formatRelative(item.started_at) ?? ''}
    {:else if column.key === 'heartbeat'}
      {formatRelative(item.last_heartbeat_at) ?? ''}
    {:else if column.key === 'actions'}
      <button
        type="button"
        class="btn btn--secondary btn--sm"
        disabled={stopping[item.id]}
        aria-label={t('admin.media.transcode.stopNamed', { name })}
        onclick={() => onstop(item.id, name)}
      >
        <AdminIcon name="stop" size={14} />{stopping[item.id]
          ? t('admin.tc.stopping')
          : t('admin.media.transcode.stop')}
      </button>
    {/if}
  {/snippet}
  {#snippet footer()}
    <p class="foot">{t('admin.tc.running.refresh')} {t('admin.tc.running.foot')}</p>
  {/snippet}
</DataTable>

<style>
  .who {
    font-weight: 600;
    color: var(--ink);
  }

  .note {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .hw {
    margin-left: 8px;
  }

  .foot {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
