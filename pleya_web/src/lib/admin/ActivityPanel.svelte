<!--
  Activiteit op scherm 20: de laatste scans en de mislukte taken, nieuwste
  eerst. Een lijst in een paneel en geen DataTable, omdat de northstar hier
  geen kolomkop tekent. De knoppen afbreken en opnieuw horen bij scherm 25
  (S10.3) en staan hier nog niet.
-->
<script lang="ts">
  import Panel from '../components/Panel.svelte';
  import StatusPill, { type PillTone } from '../components/StatusPill.svelte';
  import type { Scan } from '../api/types';
  import { t, type MessageKey } from '../i18n';
  import { formatRelative } from '../util/format';
  import { activity, countLabel, type ActivityEntry, type OverviewData } from './overview';

  let { data }: { data: OverviewData } = $props();

  const entries = $derived(activity(data));

  const SCAN_STATE: Record<string, { tone: PillTone; label: MessageKey }> = {
    queued: { tone: 'idle', label: 'admin.state.queued' },
    running: { tone: 'run', label: 'admin.state.running' },
    done: { tone: 'ok', label: 'admin.state.done' },
    failed: { tone: 'err', label: 'admin.state.failed' },
    cancelled: { tone: 'idle', label: 'admin.state.cancelled' }
  };

  function scanSub(scan: Scan): string {
    if (scan.state === 'running' || scan.state === 'queued') {
      return t('admin.activity.started', { when: formatRelative(scan.started_at) ?? '' });
    }
    const parts = [formatRelative(scan.finished_at ?? scan.started_at) ?? ''];
    parts.push(countLabel('admin.files', scan.files_seen));
    if (scan.items_created > 0) parts.push(countLabel('admin.newTitles', scan.items_created));
    if (scan.state === 'failed' && scan.last_error) parts.push(scan.last_error);
    return parts.filter(Boolean).join(' · ');
  }

  function entryTitle(entry: ActivityEntry): string {
    if (entry.kind === 'job') return t('admin.activity.jobFailed');
    return entry.library
      ? t('admin.activity.scan', { library: entry.library })
      : t('admin.activity.scanUnknown');
  }
</script>

<Panel>
  {#snippet title()}{t('admin.activity.title')}{/snippet}
  {#snippet actions()}
    <a class="all" href="/admin/activity">{t('admin.activity.viewAll')}</a>
  {/snippet}
  {#if entries.length === 0}
    <p class="empty">{t('admin.activity.empty')}</p>
  {:else}
    <ul class="list">
      {#each entries as entry (entry.kind === 'scan' ? entry.scan.id : entry.job.id)}
        <li class="row">
          <div class="body">
            <p class="t">{entryTitle(entry)}</p>
            {#if entry.kind === 'scan'}
              <p class="s">
                {scanSub(entry.scan)}{#if entry.scan.current_path}
                  · <span class="mono">{entry.scan.current_path}</span>{/if}
              </p>
            {:else}
              <p class="s">
                <span class="mono">{entry.job.kind}</span>{#if entry.job.last_error}
                  · {entry.job.last_error}{/if} · {countLabel('admin.attempts', entry.job.attempts)}
              </p>
            {/if}
          </div>
          {#if entry.kind === 'scan'}
            {@const state = SCAN_STATE[entry.scan.state] ?? SCAN_STATE['queued']!}
            <StatusPill tone={state.tone} label={t(state.label)} />
          {:else}
            <StatusPill tone="err" label={t('admin.state.failed')} />
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</Panel>

<style>
  .all {
    color: var(--ink-2);
  }

  @media (hover: hover) {
    .all:hover {
      color: var(--ink);
    }
  }

  .empty {
    margin: 0;
    font-size: 14px;
    color: var(--ink-3);
  }

  .list {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 0;
  }

  .row + .row {
    border-top: 1px solid var(--hairline);
  }

  .body {
    flex: 1;
    min-width: 0;
  }

  .t {
    margin: 0;
    font-size: 15px;
    font-weight: 500;
    color: var(--ink);
  }

  .s {
    margin: 2px 0 0;
    font-size: 13px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .s .mono {
    font-size: 12px;
  }
</style>
