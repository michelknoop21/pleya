<!--
  Versies (32): server, protocol, database en ffprobe, uit `GET /server` en
  `GET /info`. De bouwdatum uit de northstar ontbreekt: de server meldt één
  `build`-tekst met versie, toolchain en platform, en die staat hier zoals hij
  komt.
-->
<script lang="ts">
  import type { Info, ServerDetail } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { formatDate } from '../../util/format';
  import { uptimeText } from './diagnostics';
  import FactList from './FactList.svelte';

  let { server, info }: { server: ServerDetail; info: Info } = $props();

  const uptime = $derived(uptimeText(server.started_at));
</script>

<Panel>
  {#snippet title()}{t('admin.diag.versions.title')}{/snippet}
  <FactList>
    <dt>{t('admin.diag.versions.server')}</dt>
    <dd>{server.version}</dd>
    {#if server.build}
      <dt>{t('admin.diag.versions.build')}</dt>
      <dd class="mono">{server.build}</dd>
    {/if}
    <dt>{t('admin.diag.versions.protocol')}</dt>
    <dd>
      {t('admin.diag.versions.protocolValue', {
        major: info.protocol.major,
        level: info.protocol.feature_level
      })}
      · {t('admin.diag.versions.profile')} <span class="mono">{info.protocol.profile}</span>
    </dd>
    {#if server.database}
      <dt>{t('admin.diag.versions.database')}</dt>
      <dd>
        {t('admin.diag.versions.databaseValue', {
          version: server.database.version,
          schema: server.database.schema
        })}
      </dd>
    {/if}
    {#if server.ffprobe}
      <dt>ffprobe</dt>
      <dd>
        {#if server.ffprobe.found}{server.ffprobe.version ?? t('admin.diag.versions.found')}{:else}<span class="muted"
            >{t('admin.diag.versions.missing')}</span
          >{/if}
      </dd>
    {/if}
    <dt>{t('admin.diag.versions.started')}</dt>
    <dd>
      {formatDate(server.started_at) ?? server.started_at}{#if uptime}<span class="muted"> · {uptime}</span>{/if}
    </dd>
  </FactList>
</Panel>
