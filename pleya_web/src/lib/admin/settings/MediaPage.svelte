<!--
  Serverbeheer, media en streaming (northstar 28): de drie instelbare
  streamwaarden, de analyse-omgeving en de transcoderstatus met lopende
  sessies, en of downloads aanstaan. Opslaan vraagt een bevestiging, want een
  kortere streamsessie of -token raakt wie nu kijkt.
-->
<script lang="ts">
  import { adminApi } from '../../api/admin';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { describeError } from '../../api/errors';
  import type { Settings } from '../../api/types';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import Panel from '../../components/Panel.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import AdminColumns from './AdminColumns.svelte';
  import MediaAnalysisPanel from './MediaAnalysisPanel.svelte';
  import MediaDownloadsPanel from './MediaDownloadsPanel.svelte';
  import { draftFrom, loadMedia, mediaPatch, type MediaData, type MediaDraft } from './media';
  import MediaStreamsPanel from './MediaStreamsPanel.svelte';
  import MediaTranscodePanel from './MediaTranscodePanel.svelte';
  import { settingsProblem } from './settingsErrors';
  import SettingsSave from './SettingsSave.svelte';
  import { changeLines, mediaRisks } from './settings';

  let data = $state<MediaData | null>(null);
  let draft = $state<MediaDraft>({ sessionTtl: '', tokenTtl: '', maxStreams: '' });
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let stopping = $state<Record<string, boolean>>({});
  let stopTarget = $state<{ id: string; name: string } | null>(null);
  let stopOpen = $state(false);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadMedia(session.client, adminSettingsApi(session.client), adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        draft = draftFrom(result.settings);
        failure = null;
      })
      .catch((err: unknown) => {
        if (!controller.signal.aborted) failure = describeError(err);
      });
    return () => controller.abort();
  });

  const patch = $derived(data ? mediaPatch(data.settings, draft) : {});
  const transcodeOn = $derived(session.info?.capabilities.transcode === true);
  const downloadsOn = $derived(session.info?.capabilities.downloads === true);

  function saved(settings: Settings): void {
    if (data) data = { ...data, settings };
    draft = draftFrom(settings);
  }

  function askStop(id: string, name: string): void {
    stopTarget = { id, name };
    stopOpen = true;
  }

  async function stop(): Promise<void> {
    if (!stopTarget) return;
    const { id, name } = stopTarget;
    stopping[id] = true;
    problem = null;
    try {
      await adminSettingsApi(session.client).stopTranscodeSession(id);
      stopOpen = false;
      attempt += 1;
    } catch (err) {
      stopOpen = false;
      problem = settingsProblem(err, 'transcode', name);
    } finally {
      stopping[id] = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.nav.media')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.media') }]}
/>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => void stop()} onreload={() => (attempt += 1)} />
  </div>
{/if}

{#if data}
  <AdminColumns>
    {#snippet left()}
      <MediaStreamsPanel settings={data!.settings} bind:draft />
      <MediaAnalysisPanel server={data!.server} environment={data!.environment} />
      <Panel>
        {#snippet title()}{t('admin.media.env.title')}{/snippet}
        <p class="body">{t('admin.media.env.body')}</p>
      </Panel>
    {/snippet}
    {#snippet right()}
      <MediaTranscodePanel
        transcode={data!.transcode}
        users={data!.users}
        available={transcodeOn}
        {stopping}
        onstop={askStop}
      />
      <MediaDownloadsPanel enabled={downloadsOn} />
    {/snippet}
  </AdminColumns>

  <SettingsSave
    {patch}
    risks={mediaRisks(patch)}
    lines={changeLines(patch)}
    onsaved={saved}
    oncancel={() => (draft = draftFrom(data!.settings))}
  />

  <ConfirmDialog
    bind:open={stopOpen}
    busy={stopTarget ? stopping[stopTarget.id] : false}
    danger={false}
    title={t('admin.media.transcode.stopTitle')}
    message={t('admin.media.transcode.stopBody', { name: stopTarget?.name ?? '' })}
    confirmLabel={t('admin.media.transcode.stop')}
    onconfirm={() => void stop()}
  />
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

<style>
  .msg {
    margin-bottom: 14px;
  }

  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
