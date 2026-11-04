<!--
  Analyse (28): ffprobe, de timeout per bestand en het aantal werkers. Alleen
  lezen: ffprobe komt uit `GET /server` (`ffprobe.found`, gemeten bij het
  opstarten), de timeout en het aantal werkers zijn omgevingsvariabelen en komen
  uit `GET /server/environment`. Een variabele die niet gezet is staat daar
  niet in; dan werkt de server met zijn eigen standaard, en dat zeggen we.
-->
<script lang="ts">
  import type { ServerDetail } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import FactList from './FactList.svelte';
  import { ENV_FFPROBE_TIMEOUT, ENV_JOB_WORKERS, envValue, type EnvEntry } from './media';
  import { ffprobeVersion } from './settings';

  interface Props {
    server: ServerDetail;
    environment: EnvEntry[] | null;
  }

  let { server, environment }: Props = $props();

  const timeout = $derived(envValue(environment, ENV_FFPROBE_TIMEOUT));
  const workers = $derived(envValue(environment, ENV_JOB_WORKERS));
</script>

{#snippet envRow(label: string, name: string, value: string | null)}
  <dt>{label}</dt>
  <dd>
    {#if environment === null}
      <span class="muted">{t('admin.media.analysis.unreadable')}</span>
    {:else if value !== null}
      {value} <span class="muted">· {t('admin.media.analysis.env')}</span>
      <span class="sub mono">{name}</span>
    {:else}
      <span class="muted">{t('admin.media.analysis.default')}</span>
      <span class="sub mono">{name}</span>
    {/if}
  </dd>
{/snippet}

<Panel>
  {#snippet title()}{t('admin.media.analysis.title')}{/snippet}
  <FactList>
    <dt>ffprobe</dt>
    <dd>
      {#if server.ffprobe}
        <StatusPill
          variant="dot"
          tone={server.ffprobe.found ? 'ok' : 'err'}
          label={server.ffprobe.found
            ? server.ffprobe.version
              ? t('admin.media.analysis.found', { version: ffprobeVersion(server.ffprobe.version) })
              : t('admin.media.analysis.foundPlain')
            : t('admin.media.analysis.missing')}
        />
      {:else}
        <span class="muted">{t('admin.media.analysis.unreadable')}</span>
      {/if}
    </dd>
    {@render envRow(t('admin.media.analysis.timeout'), ENV_FFPROBE_TIMEOUT, timeout)}
    {@render envRow(t('admin.media.analysis.workers'), ENV_JOB_WORKERS, workers)}
  </FactList>
</Panel>
