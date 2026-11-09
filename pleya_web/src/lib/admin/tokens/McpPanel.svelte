<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import type { McpToolSummary } from '../../api/mcpHttp';
  import type { PleyaClient } from '../../api/client';
  import { describeError } from '../../api/errors';
  import Alert from '../../components/Alert.svelte';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import type { McpStatus } from './tokens';

  /** Null als de status niet te lezen was. */
  let { mcp, client }: { mcp: McpStatus | null; client: PleyaClient } = $props();
  let status = $state<McpStatus | null>(null);
  let configurable = $state(false);
  let busy = $state(false);
  let problem = $state<string | null>(null);
  let copied = $state(false);
  let tools = $state<McpToolSummary[]>([]);
  let toolsProblem = $state<string | null>(null);

  $effect(() => { status = mcp; });
  $effect(() => {
    const current = client;
    const controller = new AbortController();
    copied = false;
    configurable = false;
    busy = false;
    problem = null;
    void adminSettingsApi(current).settings(controller.signal).then((settings) => {
      if (!controller.signal.aborted) configurable = settings.mcp_enabled !== undefined;
    }).catch(() => {});
    return () => controller.abort();
  });

  $effect(() => {
    const current = client;
    const active = status?.enabled;
    const controller = new AbortController();
    tools = [];
    toolsProblem = null;
    if (active) void current.mcpTools(controller.signal).then((result) => {
      if (!controller.signal.aborted) tools = result;
    }).catch((error) => {
      if (!controller.signal.aborted) toolsProblem = describeError(error);
    });
    return () => controller.abort();
  });

  async function toggle(): Promise<void> {
    if (busy || !status) return;
    const current = client;
    const generation = current.sessionGeneration;
    busy = true;
    problem = null;
    try {
      await adminSettingsApi(current).patchSettings({ mcp_enabled: !status.enabled });
      const server = await current.server();
      if (current === client && generation === current.sessionGeneration) status = server.mcp ?? null;
    } catch (error) {
      if (current === client && generation === current.sessionGeneration) problem = describeError(error);
    } finally {
      if (current === client && generation === current.sessionGeneration) busy = false;
    }
  }

  async function copyConfiguration(): Promise<void> {
    if (!status?.url) return;
    const base = new URL(client.baseUrl, location.origin);
    const endpoint = new URL(base.pathname.replace(/\/pleya\/v1\/?$/, '') + '/mcp', base.origin).href;
    const url = /^https?:/.test(status.url) ? status.url : endpoint;
    const config = { mcpServers: { pleya: { type: 'http', url, headers: { Authorization: 'Bearer <API_TOKEN>' } } } };
    problem = null;
    try {
      await navigator.clipboard.writeText(JSON.stringify(config, null, 2));
      copied = true;
    } catch {
      problem = t('admin.tok.mcp.copyFailed');
    }
  }
</script>

<Panel>
  {#snippet title()}{t('admin.tok.mcp.title')}{/snippet}
  {#snippet actions()}
    {#if status}
      <StatusPill
        variant="dot"
        tone={status.enabled ? 'ok' : 'idle'}
        label={status.enabled ? t('admin.tok.mcp.on') : t('admin.tok.mcp.off')}
      />
    {/if}
  {/snippet}
  <Alert tone="warn" live={false}>{t('admin.tok.mcp.boundary')}</Alert>
  {#if status === null}
    <p class="note">{t('admin.tok.mcp.unreadable')}</p>
  {:else if !status.enabled}
    <p class="note">{t('admin.tok.mcp.offBody')}</p>
  {:else}
    <dl class="facts">
      {#if status.url}
        <dt>{t('admin.tok.mcp.address')}</dt>
        <dd class="mono">{status.url}</dd>
      {/if}
      <dt>{t('admin.tok.mcp.tools')}</dt>
      <dd>{plural('admin.tok.mcp.toolCount', status.tool_count)}</dd>
      <dt>{t('admin.tok.mcp.rights')}</dt>
      <dd>{t('admin.tok.mcp.rightsValue')}</dd>
    </dl>
  {/if}
  {#if toolsProblem}<Alert tone="err">{toolsProblem}</Alert>{/if}
  {#if status?.enabled && tools.length > 0}
    <details class="tool-register">
      <summary>{t('admin.tok.mcp.showTools')}</summary>
      <ul>
        {#each tools as tool (tool.name)}
          <li><code>{tool.name}</code><span>{tool.annotations?.readOnlyHint ? t('admin.tok.mcp.readOnly') : t('admin.tok.mcp.mutating')}</span></li>
        {/each}
      </ul>
    </details>
  {/if}
  {#if problem}<Alert tone="err">{problem}</Alert>{/if}
  {#if status && configurable}
    <div class="mcp-actions">
      <button type="button" class="btn btn--secondary" disabled={busy} onclick={() => void toggle()}>
        {status.enabled ? t('admin.tok.mcp.disable') : t('admin.tok.mcp.enable')}
      </button>
      {#if status.enabled && status.url}
        <button type="button" class="btn btn--secondary" onclick={() => void copyConfiguration()}>
          {copied ? t('admin.tok.mcp.copied') : t('admin.tok.mcp.copy')}
        </button>
        <p class="note">{t('admin.tok.mcp.configHint')}</p>
      {/if}
    </div>
  {/if}
</Panel>

<style>
  .tool-register { margin-top: 16px; }
  .tool-register summary { cursor: pointer; font-size: 14px; padding: 12px 0; }
  .tool-register ul { padding: 0; list-style: none; }
  .tool-register li { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px; padding: 8px 0; border-bottom: 1px solid var(--line); font-size: 12px; }
  .tool-register li code { overflow-wrap: anywhere; min-width: 0; }
  .tool-register li span { color: var(--ink-2); }
  .mcp-actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 16px; }
  .mcp-actions .note { flex-basis: 100%; }
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
