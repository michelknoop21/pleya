<!--
  Gezondheid (32): of de server klaar is (dezelfde vraag als `/readyz`, maar
  achter authenticatie en met de tellers ernaast), de taken en de MCP-laag. Het
  geheugengebruik en het aantal wachtende taken uit de northstar ontbreken: het
  contract meldt alleen lopende en mislukte taken.
-->
<script lang="ts">
  import type { ServerDetail } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import FactList from './FactList.svelte';

  let { server }: { server: ServerDetail } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.diag.health.title')}{/snippet}
  {#if server.health}
    <FactList>
      <dt class="mono">/readyz</dt>
      <dd>
        <StatusPill
          variant="dot"
          tone={server.health.ready ? 'ok' : 'err'}
          label={server.health.ready ? t('admin.diag.health.ready') : t('admin.diag.health.notReady')}
        />
      </dd>
      <dt>{t('admin.diag.health.jobs')}</dt>
      <dd>
        {t('admin.diag.health.jobsValue', {
          running: server.health.jobs_running,
          failed: server.health.jobs_failed
        })}
        {#if server.health.jobs_failed > 0}
          <a class="link" href="/admin/activity">{t('admin.diag.health.seeJobs')}</a>
        {/if}
      </dd>
      {#if server.mcp}
        <dt>MCP</dt>
        <dd>
          {#if server.mcp.enabled}
            {t('admin.diag.health.mcpOn', { count: server.mcp.tool_count })}
          {:else}
            <span class="muted">{t('admin.diag.health.mcpOff')}</span>
          {/if}
        </dd>
      {/if}
    </FactList>
  {:else}
    <p class="note">{t('admin.set.unknown')}</p>
  {/if}
</Panel>

<style>
  .link {
    margin-left: 6px;
    color: var(--ink-2);
    text-decoration: underline;
  }

  .note {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
