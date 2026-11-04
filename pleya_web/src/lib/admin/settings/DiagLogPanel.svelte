<!--
  Laatste meldingen (32, rechts): de waarschuwingen en fouten uit de ringbuffer
  van de server (`GET /server/log?level=warn`), nieuwste eerst. De buffer leeft
  in het geheugen en wordt geredigeerd voor hij gevuld wordt; een volledige log
  kent het contract niet. De regels worden bij het tonen nog eens op een
  wachtwoord in een URL nagekeken.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { formatClock } from '../../util/format';
  import { LOG_LIMIT, levelTone, maskLine, type LogEntry } from './diagnostics';

  let { entries }: { entries: LogEntry[] | null } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.diag.log.title')}{/snippet}
  {#snippet actions()}<span class="aside">{t('admin.diag.log.aside', { count: LOG_LIMIT })}</span>{/snippet}
  {#if entries === null}
    <p class="note">{t('admin.diag.log.unreadable')}</p>
  {:else if entries.length === 0}
    <p class="note">{t('admin.diag.log.empty')}</p>
  {:else}
    <ol class="log" aria-label={t('admin.diag.log.title')}>
      {#each entries as entry, i (i)}
        <li class="line">
          <span class="at">{formatClock(entry.at) ?? ''}</span>
          <span class="lvl lvl--{levelTone(entry.level)}">{entry.level}</span>
          <span class="msg"
            >{#if entry.component}<span class="comp">{entry.component}</span>{/if}{maskLine(entry.message)}</span
          >
        </li>
      {/each}
    </ol>
  {/if}
  <p class="note foot">{t('admin.diag.log.foot')}</p>
</Panel>

<style>
  .aside {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .log {
    display: grid;
    gap: 6px;
    max-height: 420px;
    margin: 0 0 12px;
    padding: 14px;
    overflow: auto;
    list-style: none;
    border-radius: var(--radius-md);
    background: var(--inset-bg);
    font-family: var(--font-mono);
    font-size: 12px;
    line-height: 1.5;
  }

  .line {
    display: grid;
    grid-template-columns: auto auto minmax(0, 1fr);
    gap: 8px;
    align-items: baseline;
  }

  .at {
    color: var(--ink-3);
  }

  .lvl--warn {
    color: var(--warn-ink);
  }

  .lvl--err {
    color: var(--danger-ink);
  }

  .lvl--idle {
    color: var(--ink-3);
  }

  .msg {
    color: var(--ink-2);
    overflow-wrap: anywhere;
  }

  .comp {
    margin-right: 6px;
    color: var(--ink);
  }

  .note {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  .foot {
    font-size: 12.5px;
    line-height: 1.5;
  }
</style>
