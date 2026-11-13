<!--
  Logregels uit de ringbuffer van de server (`GET /server/log`), nieuwste
  eerst: tijd, niveau, en het bericht met het subsysteem ervoor. Gedeeld door
  Diagnostiek (32) en Activiteit. De regels worden bij het tonen nog eens op
  een wachtwoord in een URL nagekeken.
-->
<script lang="ts">
  import { formatClock } from '../../util/format';
  import { levelTone, maskLine, type LogEntry } from './diagnostics';

  let { entries, label }: { entries: LogEntry[]; label: string } = $props();
</script>

<ol class="log" aria-label={label}>
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

<style>
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
</style>
