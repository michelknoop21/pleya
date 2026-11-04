<!--
  Het paneel Fouten van scherm 25: mislukte taken met hun melding en een knop
  om het opnieuw te proberen (`POST /jobs/{id}/retry`), bibliotheken waarvan de
  laatste scan mislukte met een knop Nu scannen (`POST /libraries/{id}/scan`),
  en elke root die niet gemount is met een link naar Opslag.

  De northstar tekent ook Overslaan. De server kent geen route om een fout
  weg te zetten, dus die knop is er niet; een mislukte job blijft staan tot hij
  opnieuw is geprobeerd. De regel onder de lijst zegt dat.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import type { Job, Library } from '../api/types';
  import {
    attemptsLine,
    failedJobTitle,
    failedScanDetail,
    failedScanWhen,
    failureDetail,
    type FailureItem
  } from './activity';

  interface Props {
    items: FailureItem[];
    /** Jobs waarvoor nu een nieuwe poging wordt aangevraagd. */
    retrying: Record<string, boolean>;
    onretry: (job: Job, name: string) => void;
    /** Bibliotheken waarvoor nu een scan wordt aangevraagd, op id. */
    scanning?: Record<string, boolean>;
    onscan?: (library: Library) => void;
    now?: number;
  }

  let { items, retrying, onretry, scanning = {}, onscan = () => {}, now = Date.now() }: Props = $props();

  function keyOf(item: FailureItem): string {
    if (item.kind === 'job') return item.job.id;
    if (item.kind === 'scan') return `scan-${item.scan.id}`;
    return item.root.path;
  }

  const hasJobs = $derived(items.some((i) => i.kind === 'job'));
</script>

<Panel>
  {#snippet title()}{t('admin.act.failures.title')}{/snippet}
  {#snippet actions()}
    {#if items.length > 0}
      <span class="count">{t('admin.act.failures.open', { count: items.length })}</span>
    {/if}
  {/snippet}
  {#if items.length === 0}
    <p class="empty">{t('admin.act.failures.empty')}</p>
  {:else}
    <ul class="list">
      {#each items as item (keyOf(item))}
        <li class="row" data-failure={keyOf(item)}>
          {#if item.kind === 'job'}
            {@const name = failedJobTitle(item.job, item.library)}
            <div class="what">
              <p class="name">{name}</p>
              <p class="sub mono">{item.job.kind}</p>
            </div>
            <div class="why">
              <p>{failureDetail(item.job)}</p>
              <p>{attemptsLine(item.job)}</p>
            </div>
            <div class="acts">
              <button
                type="button"
                class="btn btn--secondary btn--sm"
                disabled={retrying[item.job.id]}
                aria-label={t('admin.act.failures.retryNamed', { name })}
                onclick={() => onretry(item.job, name)}
              >
                <AdminIcon name="refresh" size={14} />{t('admin.act.failures.retry')}
              </button>
            </div>
          {:else if item.kind === 'scan'}
            <div class="what">
              <p class="name">{t('admin.act.failures.scanTitle', { library: item.library.title })}</p>
              <p class="sub">{t('admin.act.failures.scanWhen', { when: failedScanWhen(item.scan, now) })}</p>
            </div>
            <div class="why">
              <p>{failedScanDetail(item.scan)}</p>
            </div>
            <div class="acts">
              <button
                type="button"
                class="btn btn--secondary btn--sm"
                disabled={scanning[item.library.id]}
                aria-label={t('admin.act.failures.scanRetryNamed', { library: item.library.title })}
                onclick={() => onscan(item.library)}
              >
                <AdminIcon name="scan" size={14} />{t('admin.act.failures.scanRetry')}
              </button>
            </div>
          {:else}
            <div class="what">
              <p class="name">{t('admin.act.failures.rootTitle')}</p>
              <p class="sub mono">{item.root.path}</p>
            </div>
            <div class="why"><p>{t('admin.act.failures.rootBody')}</p></div>
            <div class="acts">
              <a class="btn btn--secondary btn--sm" href="/admin/storage">
                <AdminIcon name="drive" size={14} />{t('admin.act.failures.storage')}
              </a>
            </div>
          {/if}
        </li>
      {/each}
    </ul>
    {#if hasJobs}<p class="hint">{t('admin.act.failures.note')}</p>{/if}
  {/if}
</Panel>

<style>
  .count {
    font-size: 13px;
    color: var(--ink-3);
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
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) 150px;
    align-items: center;
    gap: 8px 24px;
    padding: 12px 0;
  }

  .row + .row {
    border-top: 1px solid var(--hairline);
  }

  .name {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--ink);
  }

  .sub {
    margin: 3px 0 0;
    font-size: 12px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .why p {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .acts {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  @media (max-width: 899px) {
    .row {
      grid-template-columns: minmax(0, 1fr);
    }

    .acts {
      justify-content: flex-start;
    }
  }
</style>
