<!--
  Het paneel Bezig van scherm 25: wachtende en lopende scans, en lopende taken
  van een andere soort. Per scan de tellers die de server meldt en het
  bestand waar hij nu mee bezig is; Afbreken stopt de job achter de scan.

  Geen voortgangsbalk en geen percentage: `Scan` draagt het aantal gezien
  bestanden maar geen totaal, en een geschat percentage zou verzonnen zijn.
  Ook "2 werkers" uit de northstar ontbreekt: het contract noemt geen werkers.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import type { Job } from '../api/types';
  import { runningJobTitle, scanStats, startedLine, type RunningItem } from './activity';
  import { countLabel } from './overview';

  interface Props {
    items: RunningItem[];
    now: number;
    /** Jobs waarvoor nu een afbreekaanvraag loopt. */
    stopping: Record<string, boolean>;
    onstop: (job: Job, name: string) => void;
  }

  let { items, now, stopping, onstop }: Props = $props();

  function nameOf(item: RunningItem): string {
    if (item.kind === 'job') return runningJobTitle(item.job);
    return item.library
      ? t('admin.act.history.scan', { library: item.library })
      : t('admin.act.history.scanUnknown');
  }
</script>

<Panel>
  {#snippet title()}{t('admin.act.running.title')}{/snippet}
  {#snippet actions()}
    {#if items.length > 0}
      <span class="count">{countLabel('admin.act.running.tasks', items.length)}</span>
    {/if}
  {/snippet}
  {#if items.length === 0}
    <p class="empty">{t('admin.act.running.empty')}</p>
  {:else}
    <ul class="list">
      {#each items as item (item.kind === 'scan' ? item.scan.id : item.job.id)}
        {@const name = nameOf(item)}
        {@const job = item.job}
        <li class="row" data-running={item.kind === 'scan' ? item.scan.id : item.job.id}>
          <div class="body">
            <div class="top">
              <p class="name">{name}</p>
              {#if item.kind === 'scan'}<p class="when">{startedLine(item.scan, now)}</p>{/if}
            </div>
            {#if item.kind === 'scan'}
              {#if item.scan.state === 'running'}
                <p class="stats">{scanStats(item.scan).join(' · ')}</p>
                {#if item.scan.current_path}
                  <p class="path mono">{item.scan.current_path}</p>
                {/if}
              {/if}
            {:else}
              <p class="stats">
                <span class="mono">{item.job.kind}</span> · {countLabel('admin.attempts', item.job.attempts)}
              </p>
            {/if}
          </div>
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
        </li>
      {/each}
    </ul>
    <p class="hint">{t('admin.act.running.refresh')}</p>
  {/if}
</Panel>

<style>
  .count {
    padding: 4px 10px;
    border-radius: var(--radius-pill);
    background: var(--fill);
    font-size: 12px;
    font-weight: 600;
    color: var(--ink-2);
  }

  .empty,
  .hint {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  .hint {
    margin-top: 12px;
  }

  .list {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    align-items: flex-start;
    gap: 16px;
    padding: 4px 0;
  }

  .row + .row {
    margin-top: 12px;
    padding-top: 16px;
    border-top: 1px solid var(--hairline);
  }

  .body {
    flex: 1;
    min-width: 0;
  }

  .top {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: 2px 16px;
  }

  .name {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--ink);
  }

  .when {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .stats,
  .path {
    margin: 6px 0 0;
    font-size: 13px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .path {
    margin-top: 4px;
    font-size: 12px;
  }

  @media (max-width: 899px) {
    .row {
      flex-direction: column;
      gap: 12px;
    }
  }
</style>
