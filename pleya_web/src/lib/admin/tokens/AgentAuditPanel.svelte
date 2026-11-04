<!--
  Laatste beheeracties via agents (34, links onder): de nieuwste tien regels
  van `GET /audit?source=mcp`. Een regel is tijd, de operatie (de operationId uit
  het contract, in monoletter), het doel, wie het deed en de uitkomst. De
  server levert geen toolnaam of omschrijving per actie, dus die staan er niet;
  wie het deed is de naam van het token als dat nog leeft, anders de gebruiker.
-->
<script lang="ts">
  import type { AuditEntry } from '../../api/adminTokens';
  import Panel from '../../components/Panel.svelte';
  import StatusPill, { type PillTone } from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import { formatDayClock } from '../../util/format';
  import { actorText, type TokensData } from './tokens';

  interface Props {
    /** Null als het log niet te lezen was. */
    entries: AuditEntry[] | null;
    data: Pick<TokensData, 'rows' | 'users'>;
  }

  let { entries, data }: Props = $props();

  const OUTCOME: Record<string, { tone: PillTone; key: 'ok' | 'denied' | 'failed' }> = {
    ok: { tone: 'ok', key: 'ok' },
    denied: { tone: 'err', key: 'denied' },
    failed: { tone: 'err', key: 'failed' }
  };
</script>

<Panel>
  {#snippet title()}{t('admin.tok.audit.title')}{/snippet}
  {#snippet actions()}<span class="sub">{t('admin.tok.audit.sub')}</span>{/snippet}
  {#if entries === null}
    <p class="note">{t('admin.tok.audit.unreadable')}</p>
  {:else if entries.length === 0}
    <p class="note">{t('admin.tok.audit.empty')}</p>
  {:else}
    <ul class="list">
      {#each entries as entry (entry.id)}
        {@const who = actorText(entry, data)}
        {@const outcome = OUTCOME[entry.outcome]}
        <li class="row" data-audit={entry.id}>
          <span class="time">{formatDayClock(entry.at) ?? ''}</span>
          <span class="text">
            <code class="op">{entry.operation}</code>
            <span class="meta">
              {#if entry.target}{entry.target}{/if}
              {#if who}{entry.target ? ' · ' : ''}{t('admin.tok.audit.by', { who })}{/if}
            </span>
          </span>
          <StatusPill
            size="sm"
            tone={outcome?.tone ?? 'idle'}
            label={outcome ? t(`admin.tok.audit.${outcome.key}`) : entry.outcome}
          />
        </li>
      {/each}
    </ul>
  {/if}
</Panel>

<style>
  .sub {
    font-size: 13px;
    color: var(--ink-3);
  }

  .note {
    margin: 0;
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--ink-2);
  }

  .list {
    display: grid;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: grid;
    grid-template-columns: 86px minmax(0, 1fr) auto;
    align-items: center;
    gap: 14px;
    padding: 12px 0;
    border-bottom: 1px solid var(--hairline);
  }

  .row:last-child {
    border-bottom: 0;
  }

  .time {
    font-size: 13px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .text {
    display: grid;
    min-width: 0;
  }

  .op {
    font-family: var(--font-mono);
    font-size: 13px;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .meta {
    font-size: 12.5px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  @media (max-width: 479px) {
    .row {
      grid-template-columns: minmax(0, 1fr) auto;
    }

    .time {
      grid-column: 1 / -1;
    }
  }
</style>
