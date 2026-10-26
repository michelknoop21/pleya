<!--
  Serverbeheer, diagnostiek (northstar 32): versies, capabilities, gezondheid,
  omgeving en de laatste meldingen. Alleen lezen. Rapport voor support bewaart
  dezelfde gegevens als tekstbestand in de browser; er gaat niets naar een
  server, en niets daarin kan een geheim zijn dat het scherm niet ook toont.
-->
<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import { describeError } from '../../api/errors';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import AdminColumns from './AdminColumns.svelte';
  import DiagCapabilitiesPanel from './DiagCapabilitiesPanel.svelte';
  import DiagEnvironmentPanel from './DiagEnvironmentPanel.svelte';
  import DiagHealthPanel from './DiagHealthPanel.svelte';
  import DiagLogPanel from './DiagLogPanel.svelte';
  import DiagVersionsPanel from './DiagVersionsPanel.svelte';
  import {
    buildReport,
    loadDiagnostics,
    reportFileName,
    saveTextFile,
    type DiagnosticsData
  } from './diagnostics';

  let data = $state<DiagnosticsData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadDiagnostics(session.client, adminSettingsApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (!controller.signal.aborted) failure = describeError(err);
      });
    return () => controller.abort();
  });

  function download(): void {
    if (!data) return;
    const now = new Date();
    saveTextFile(reportFileName(now), buildReport(data, now));
  }
</script>

<AdminPageHead
  title={t('admin.nav.diagnostics')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.diagnostics') }]}
>
  {#snippet actions()}
    <button type="button" class="btn btn--secondary btn--sm" disabled={!data} onclick={download}>
      {t('admin.diag.report')}
    </button>
  {/snippet}
</AdminPageHead>

{#if data}
  <AdminColumns>
    {#snippet left()}
      <DiagVersionsPanel server={data!.server} info={data!.info} />
      <DiagCapabilitiesPanel info={data!.info} />
      <DiagHealthPanel server={data!.server} />
    {/snippet}
    {#snippet right()}
      <DiagEnvironmentPanel entries={data!.environment} />
      <DiagLogPanel entries={data!.log} />
    {/snippet}
  </AdminColumns>
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}
