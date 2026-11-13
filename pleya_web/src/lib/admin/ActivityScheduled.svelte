<!--
  Geplande taken (doelbeeld Activiteit): per bibliotheek de scanronde met zijn
  schema en de laatste keer. De ronde knop start de scan nu
  (`POST /libraries/{id}/scan`); Schema gaat naar de bibliotheek, waar het
  interval te wijzigen is. Wat hier ontbreekt en waarom staat in
  activitySchedule.ts.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import type { Library } from '../api/types';
  import { t } from '../i18n';
  import type { ScheduledRow } from './activitySchedule';

  interface Props {
    rows: ScheduledRow[];
    /** Bibliotheken waarvoor nu een scanaanvraag loopt. */
    scanning: Record<string, boolean>;
    onscan: (library: Library) => void;
  }

  let { rows, scanning, onscan }: Props = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.act.sched.title')}{/snippet}
  {#if rows.length === 0}
    <p class="help">{t('admin.act.sched.empty')}</p>
  {:else}
    <p class="help">{t('admin.act.sched.help')}</p>
    <ul class="list">
      {#each rows as row (row.library.id)}
        <li class="row" data-scheduled={row.library.id}>
          <button
            type="button"
            class="run"
            disabled={!row.canRun || scanning[row.library.id]}
            aria-label={t('admin.act.sched.runNamed', { name: row.title })}
            onclick={() => onscan(row.library)}
          >
            <AdminIcon name="play" size={16} />
          </button>
          <div class="body">
            <p class="name">{row.title}</p>
            <p class="sub">{row.detail}</p>
          </div>
          <dl class="fact">
            <dt>{t('admin.act.sched.schedule')}</dt>
            <dd>{row.schedule}</dd>
          </dl>
          {#if row.next !== undefined}
            <dl class="fact">
              <dt>{t('admin.act.sched.next')}</dt>
              <dd>{row.next ?? t('admin.act.sched.noNext')}</dd>
            </dl>
          {/if}
          <dl class="fact">
            <dt>{t('admin.act.sched.last')}</dt>
            <dd><StatusPill variant="dot" tone={row.lastTone} label={row.last} /></dd>
          </dl>
          <a
            class="btn btn--secondary btn--sm"
            href={`/admin/libraries/${row.library.id}`}
            aria-label={t('admin.act.sched.editNamed', { name: row.library.title })}
          >
            {t('admin.act.sched.schedule')}
          </a>
        </li>
      {/each}
    </ul>
  {/if}
</Panel>

<style>
  .help {
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }

  .list {
    margin: 10px 0 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px 16px;
    padding: 14px 0;
    border-top: 1px solid var(--hairline);
  }

  .row:last-child {
    padding-bottom: 0;
  }

  .run {
    display: inline-flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: var(--touch-target);
    height: var(--touch-target);
    padding: 0;
    border: 1px solid var(--hairline-strong);
    border-radius: var(--radius-pill);
    background: transparent;
    color: var(--ink);
    cursor: pointer;
  }

  .run:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .run:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }

  @media (hover: hover) {
    .run:not(:disabled):hover {
      border-color: var(--ink);
    }
  }

  .body {
    flex: 2 1 220px;
    min-width: 0;
  }

  .name {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .sub {
    margin: 2px 0 0;
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .fact {
    flex: 1 1 170px;
    min-width: 0;
    margin: 0;
  }

  .fact dt {
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--ink-3);
  }

  .fact dd {
    margin: 2px 0 0;
    font-size: 14px;
    color: var(--ink);
  }
</style>
