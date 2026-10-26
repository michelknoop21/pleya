<!--
  De lijst van scherm 35: gemaakt, inhoud, grootte, status, hersteltest en per
  rij de twee acties. Onder 900 stapelt de tabel (DataTable `stack`) zoals de
  northstar 35@393: tijdstip, inhoud, grootte en uitkomst onder elkaar, de
  acties rechts.

  Een actie staat alleen bij een rij waar hij kan: Hersteltest en Terugzetten
  bij een geslaagde back-up, niets bij een mislukte of verdwenen. Zolang er een
  back-up of hersteltest loopt zijn ze uit, met de reden als titel; de server
  weigert ze anders toch met `server.backup_busy`.

  De downloadknop uit de northstar ontbreekt: er is bewust geen route.
-->
<script lang="ts">
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import type { Backup } from '../../api/types';
  import { t } from '../../i18n';
  import { formatBytes, formatDayClock } from '../../util/format';
  import { canRestore, canVerify, contentLine, failureLine, secretsLabel, statusChip, testChip, triggerLabel } from './backups';

  interface Props {
    items: Backup[];
    now: number;
    /** Het tijdstip van de dagelijkse back-up, voor de lege staat. */
    schedule: string;
    busy: boolean;
    onverify: (backup: Backup) => void;
    onrestore: (backup: Backup) => void;
  }

  let { items, now, schedule, busy, onverify, onrestore }: Props = $props();

  const columns: Column[] = [
    { key: 'made', label: t('admin.bak.col.made') },
    { key: 'content', label: t('admin.bak.col.content') },
    { key: 'size', label: t('admin.bak.col.size') },
    { key: 'status', label: t('admin.bak.col.status') },
    { key: 'test', label: t('admin.bak.col.test') },
    { key: 'actions', label: t('admin.bak.col.actions'), align: 'end', hideLabel: true }
  ];

  const when = (b: Backup) => formatDayClock(b.started_at, now) ?? b.started_at;
</script>

<DataTable
  {columns}
  rows={items}
  label={t('admin.bak.list.title')}
  rowKey={(row) => row.id}
  rowData={(row) => ({ 'data-backup': row.id, 'data-status': row.status })}
  stack
>
  {#snippet empty()}{t('admin.bak.empty', { time: schedule })}{/snippet}
  {#snippet cell(backup, column)}
    {#if column.key === 'made'}
      <span class="when">{when(backup)}</span>
      <span class="note">{triggerLabel(backup)}</span>
    {:else if column.key === 'content'}
      {contentLine(backup)}
      <span class="note">{secretsLabel(backup)}</span>
    {:else if column.key === 'size'}
      {#if backup.size_bytes !== null}
        {formatBytes(backup.size_bytes)}
      {:else}
        <span class="muted">{t('admin.bak.size.unknown')}</span>
      {/if}
    {:else if column.key === 'status'}
      {@const chip = statusChip(backup)}
      <StatusPill size="sm" tone={chip.tone} label={chip.label} />
    {:else if column.key === 'test'}
      {#if backup.status === 'ok'}
        {@const test = testChip(backup, now)}
        <StatusPill size="sm" tone={test.chip.tone} label={test.chip.label} />
        {#if test.detail}<span class="note">{test.detail}</span>{/if}
      {:else if backup.failure_code}
        <span class="muted">{failureLine(backup.failure_code)}</span>
      {:else}
        <span class="muted">·</span>
      {/if}
    {:else if column.key === 'actions'}
      <span class="actions">
        {#if canVerify(backup)}
          <button
            type="button"
            class="btn btn--secondary btn--sm"
            disabled={busy}
            title={busy ? t('admin.bak.action.busy') : undefined}
            aria-label={t('admin.bak.action.verifyFor', { when: when(backup) })}
            onclick={() => onverify(backup)}
          >
            {t('admin.bak.action.verify')}
          </button>
        {/if}
        {#if canRestore(backup)}
          <button
            type="button"
            class="btn btn--secondary btn--sm"
            disabled={busy}
            title={busy ? t('admin.bak.action.busy') : undefined}
            aria-label={t('admin.bak.action.restoreFor', { when: when(backup) })}
            onclick={() => onrestore(backup)}
          >
            {t('admin.bak.action.restore')}
          </button>
        {/if}
      </span>
    {/if}
  {/snippet}
</DataTable>

<style>
  .when {
    font-weight: 600;
  }

  .note,
  .muted {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    color: var(--ink-3);
  }

  .actions {
    display: inline-flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }

  @media (max-width: 899px) {
    .actions {
      justify-content: flex-start;
    }
  }
</style>
