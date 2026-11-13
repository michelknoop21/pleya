<!--
  Log (doelbeeld Activiteit): de laatste regels uit de ringbuffer van de server
  (`GET /server/log?level=…&limit=…`), nieuwste eerst. Het niveau is de
  ondergrens die de server toepast; zoeken filtert de opgehaalde regels in de
  browser, want de route kent geen zoekparameter.

  Het paneel leest zelf en los van de rest van de pagina: is de log niet te
  lezen, dan staat dat hier en blijven scans en taken gewoon werken.
  Downloaden uit het doelbeeld is een voorstel en staat er niet; een route naar
  een volledige log bestaat niet.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Field from '../components/Field.svelte';
  import Panel from '../components/Panel.svelte';
  import Select, { type SelectOption } from '../components/Select.svelte';
  import { adminSettingsApi } from '../api/adminSettings';
  import type { LogLevel } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import type { LogEntry } from './settings/diagnostics';
  import LogLines from './settings/LogLines.svelte';

  /** Ruim onder de 500 van de buffer; genoeg om in te zoeken. */
  const LIMIT = 200;

  const levels: SelectOption[] = [
    { value: 'warn', label: t('admin.act.log.level.warn') },
    { value: 'debug', label: t('admin.act.log.level.all') },
    { value: 'error', label: t('admin.act.log.level.error') }
  ];

  let level = $state('warn');
  let query = $state('');
  let attempt = $state(0);
  /** Undefined tijdens het laden, null als de log niet te lezen was. */
  let entries = $state<LogEntry[] | null | undefined>(undefined);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    adminSettingsApi(session.client)
      .log(level as LogLevel, LIMIT, controller.signal)
      .then((result) => (entries = result))
      .catch(() => {
        if (!controller.signal.aborted) entries = null;
      });
    return () => controller.abort();
  });

  const shown = $derived.by(() => {
    const needle = query.trim().toLowerCase();
    if (!entries || needle === '') return entries ?? [];
    return entries.filter((e) => `${e.component ?? ''} ${e.message}`.toLowerCase().includes(needle));
  });
</script>

<Panel>
  {#snippet title()}{t('admin.act.log.title')}{/snippet}
  {#snippet actions()}
    <button type="button" class="btn btn--secondary btn--sm" onclick={() => (attempt += 1)}>
      <AdminIcon name="refresh" size={16} />{t('admin.act.log.refresh')}
    </button>
  {/snippet}
  <div class="filters">
    <div class="filter"><Select label={t('admin.act.log.level')} options={levels} bind:value={level} /></div>
    <div class="filter">
      <Field label={t('admin.act.log.search')} type="search" bind:value={query} autocomplete="off" />
    </div>
  </div>
  {#if entries === null}
    <p class="note">{t('admin.diag.log.unreadable')}</p>
  {:else if entries === undefined}
    <p class="note">{t('admin.act.log.loading')}</p>
  {:else if entries.length === 0}
    <p class="note">{t('admin.act.log.empty')}</p>
  {:else if shown.length === 0}
    <p class="note">{t('admin.act.log.noMatch', { query: query.trim() })}</p>
  {:else}
    <LogLines entries={shown} label={t('admin.act.log.title')} />
  {/if}
  <p class="note foot">{t('admin.diag.log.foot')}</p>
</Panel>

<style>
  .filters {
    display: flex;
    flex-wrap: wrap;
    gap: 12px 16px;
    margin-bottom: 14px;
  }

  .filter {
    flex: 1 1 200px;
    min-width: 0;
    max-width: 320px;
  }

  .note {
    margin: 0 0 12px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .foot {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
  }
</style>
