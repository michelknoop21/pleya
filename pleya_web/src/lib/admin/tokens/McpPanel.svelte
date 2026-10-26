<!--
  MCP (34, rechts boven): wat `GET /server` over de MCP-laag zegt, namelijk of
  hij aanstaat, op welk adres en hoeveel tools hij aanbiedt. Het contract
  draagt niet meer: de northstar-regels over transport en de verdeling van de
  tools, de knop "Configuratie kopiëren" en het uitzetten van MCP staan er
  daarom niet (zie `tokens.ts`). Zolang `capabilities.mcp` onwaar is, zegt het
  object `enabled: false` en is er geen adres; dan staat hier alleen dat het uit
  staat.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import type { McpStatus } from './tokens';

  /** Null als de status niet te lezen was. */
  let { mcp }: { mcp: McpStatus | null } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.tok.mcp.title')}{/snippet}
  {#snippet actions()}
    {#if mcp}
      <StatusPill
        variant="dot"
        tone={mcp.enabled ? 'ok' : 'idle'}
        label={mcp.enabled ? t('admin.tok.mcp.on') : t('admin.tok.mcp.off')}
      />
    {/if}
  {/snippet}
  {#if mcp === null}
    <p class="note">{t('admin.tok.mcp.unreadable')}</p>
  {:else if !mcp.enabled}
    <p class="note">{t('admin.tok.mcp.offBody')}</p>
  {:else}
    <dl class="facts">
      {#if mcp.url}
        <dt>{t('admin.tok.mcp.address')}</dt>
        <dd class="mono">{mcp.url}</dd>
      {/if}
      <dt>{t('admin.tok.mcp.tools')}</dt>
      <dd>{plural('admin.tok.mcp.toolCount', mcp.tool_count)}</dd>
      <dt>{t('admin.tok.mcp.rights')}</dt>
      <dd>{t('admin.tok.mcp.rightsValue')}</dd>
    </dl>
  {/if}
</Panel>

<style>
  .note {
    margin: 0;
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--ink-2);
  }

  .facts {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    gap: 8px 18px;
    margin: 0;
    font-size: 14px;
  }

  dt {
    color: var(--ink-3);
  }

  dd {
    margin: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .mono {
    font-family: var(--font-mono);
    font-size: 13px;
  }

  @media (max-width: 479px) {
    .facts {
      grid-template-columns: minmax(0, 1fr);
      gap: 2px;
    }

    dd {
      margin-bottom: 8px;
    }
  }
</style>
