<!--
  Laatste meldingen (32, rechts): de waarschuwingen en fouten uit de ringbuffer
  van de server (`GET /server/log?level=warn`), nieuwste eerst. De buffer leeft
  in het geheugen en wordt geredigeerd voor hij gevuld wordt; een volledige log
  kent het contract niet. LogLines tekent de regels.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { LOG_LIMIT, type LogEntry } from './diagnostics';
  import LogLines from './LogLines.svelte';

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
    <LogLines {entries} label={t('admin.diag.log.title')} />
  {/if}
  <p class="note foot">{t('admin.diag.log.foot')}</p>
</Panel>

<style>
  .aside {
    font-size: 12.5px;
    color: var(--ink-3);
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
