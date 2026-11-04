<!--
  Ingelogde toestellen (31, rechts): elk toestel van elke gebruiker met
  Intrekken (`DELETE /sessions/{id}`). Het toestel waarmee je nu kijkt heeft
  geen knop, want intrekken zou jezelf uitloggen. API-tokens staan hier niet.
  Een toestel zonder naam heet "Onbekend toestel" met de dag van aanmelden.
  Onderaan staat Oude toestellen opruimen (DEC-164).
-->
<script lang="ts">
  import type { User } from '../../api/types';
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import { formatDate, formatRelative } from '../../util/format';
  import DeviceCleanup from '../DeviceCleanup.svelte';
  import { deviceLabel, isUnnamed } from '../sessionCleanup';
  import type { DeviceRow } from './security';

  interface Props {
    devices: DeviceRow[];
    unreadable: User[];
    revoking: Record<string, boolean>;
    onrevoke: (row: DeviceRow) => void;
    /** Intrekken voor het opruimen; de gewone knop vraagt eerst om bevestiging via onrevoke. */
    cleanupRevoke: (sessionId: string) => Promise<unknown>;
    oncleaned: () => Promise<void> | void;
  }

  let { devices, unreadable, revoking, onrevoke, cleanupRevoke, oncleaned }: Props = $props();

  const cleanupItems = $derived(devices.map((row) => ({ session: row.session, user: row.user.username })));

  const columns: Column[] = [
    { key: 'device', label: t('admin.sec.devices.col.device') },
    { key: 'user', label: t('admin.sec.devices.col.user') },
    { key: 'seen', label: t('admin.sec.devices.col.seen') },
    { key: 'actions', label: t('admin.sec.devices.col.actions'), align: 'end', hideLabel: true }
  ];
</script>

<DataTable
  {columns}
  rows={devices}
  label={t('admin.sec.devices.title')}
  rowKey={(row) => row.session.id}
  rowData={(row) => ({ 'data-session': row.session.id })}
  stack
>
  {#snippet title()}{t('admin.sec.devices.title')}{/snippet}
  {#snippet actions()}
    <span class="count">{plural('admin.sec.devices.count', devices.length)}</span>
  {/snippet}
  {#snippet empty()}{t('admin.sec.devices.empty')}{/snippet}
  {#snippet cell(row, column)}
    {#if column.key === 'device'}
      {deviceLabel(row.session)}
      {#if isUnnamed(row.session)}
        <span class="sub">{t('admin.devices.signedInOn', { date: formatDate(row.session.created_at) ?? '' })}</span>
      {/if}
      {#if row.session.kind === 'legacy'}<span class="sub">{t('admin.sec.devices.legacy')}</span>{/if}
    {:else if column.key === 'user'}
      {row.user.username}
    {:else if column.key === 'seen'}
      {formatRelative(row.session.last_seen_at) ?? ''}
    {:else if column.key === 'actions'}
      {#if row.session.current}
        <StatusPill size="sm" tone="ok" label={t('admin.users.devices.thisOne')} />
      {:else}
        <button
          type="button"
          class="btn btn--secondary btn--sm"
          disabled={revoking[row.session.id]}
          aria-label={t('admin.sec.devices.revokeNamed', {
            device: deviceLabel(row.session, true),
            user: row.user.username
          })}
          onclick={() => onrevoke(row)}
        >
          {t('admin.sec.devices.revoke')}
        </button>
      {/if}
    {/if}
  {/snippet}
  {#snippet footer()}
    {#if unreadable.length > 0}
      <p class="foot foot--warn">
        {t('admin.sec.devices.unreadable', { users: unreadable.map((u) => u.username).join(', ') })}
      </p>
    {/if}
    <p class="foot">{t('admin.sec.devices.foot')}</p>
    <DeviceCleanup items={cleanupItems} revoke={cleanupRevoke} ondone={oncleaned} />
  {/snippet}
</DataTable>

<style>
  .count {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .sub {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    font-weight: 400;
    color: var(--ink-3);
  }

  .foot {
    margin: 0 0 6px;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .foot--warn {
    color: var(--warn-ink);
  }
</style>
