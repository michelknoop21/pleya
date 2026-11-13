<!--
  Taken en activiteit op het overzicht: de laatste scans en de mislukte taken,
  nieuwste eerst. Een lijst in een paneel en geen DataTable, omdat het
  doelbeeld hier geen kolomkop tekent.

  Dezelfde twee handelingen als scherm 25: Afbreken bij een scan die wacht of
  loopt (via zijn job, `POST /jobs/{id}/cancel`) en Nu opnieuw bij een mislukte
  taak (`POST /jobs/{id}/retry`). Het paneel stuurt zelf niets; het overzicht
  doet de aanvraag en toont de melding.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import StatusPill, { type PillTone } from '../components/StatusPill.svelte';
  import type { Job, Scan } from '../api/types';
  import { t, type MessageKey } from '../i18n';
  import { formatRelative } from '../util/format';
  import { failedJobTitle, scanJob } from './activity';
  import { activity, countLabel, libraryTitle, type ActivityEntry, type OverviewData } from './overview';

  interface Props {
    data: OverviewData;
    /** Jobs waarvoor nu een afbreekaanvraag loopt. */
    stopping?: Record<string, boolean>;
    /** Jobs waarvoor nu een nieuwe poging wordt aangevraagd. */
    retrying?: Record<string, boolean>;
    onstop?: (job: Job, name: string) => void;
    onretry?: (job: Job, name: string) => void;
  }

  let { data, stopping = {}, retrying = {}, onstop = () => {}, onretry = () => {} }: Props = $props();

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
          <div class="end">
            {#if entry.kind === 'scan'}
              {@const state = SCAN_STATE[entry.scan.state] ?? SCAN_STATE['queued']!}
              {@const job = scanJob(data.jobs, entry.scan)}
              {@const name = entryTitle(entry)}
              <StatusPill tone={state.tone} label={t(state.label)} />
              {#if job}
                <button
                  type="button"
                  class="btn btn--secondary btn--sm"
                  disabled={stopping[job.id] || job.cancel_requested_at !== null}
                  aria-label={t('admin.act.running.stopNamed', { name })}
                  onclick={() => onstop(job, name)}
                >
                  <AdminIcon name="stop" size={14} />{job.cancel_requested_at !== null || stopping[job.id]
                    ? t('admin.act.running.stopping')
                    : t('admin.act.running.stop')}
                </button>
              {/if}
            {:else}
              {@const name = failedJobTitle(entry.job, libraryTitle(data.libraries, entry.job.library_id))}
              <StatusPill tone="err" label={t('admin.state.failed')} />
              <button
                type="button"
                class="btn btn--secondary btn--sm"
                disabled={retrying[entry.job.id]}
                aria-label={t('admin.act.failures.retryNamed', { name })}
                onclick={() => onretry(entry.job, name)}
              >
                <AdminIcon name="refresh" size={14} />{t('admin.act.failures.retry')}
              </button>
            {/if}
          </div>
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

  .end {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
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

  /* Onder 900 staan status en knop onder de tekst, anders blijft er voor een
     pad of foutmelding een kolom van een paar woorden over. */
  @media (max-width: 899px) {
    .row {
      flex-direction: column;
      align-items: stretch;
      gap: 10px;
    }

    .end {
      justify-content: flex-start;
    }
  }
</style>
