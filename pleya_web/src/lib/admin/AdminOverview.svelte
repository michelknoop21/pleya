<!--
  Serverbeheer, overzicht: kruimel, servernaam met de status en rechts Scan
  alle bibliotheken; een melding per niet-gemounte opslagroot; dan Nu aan het
  kijken als kaarten per kijker; daaronder Taken en activiteit naast Server
  (2fr 1fr vanaf 1200, daaronder één kolom); en onderaan de vier tellers als
  links naar hun sectie. Deze volgorde wijkt bewust af van northstar 20, die
  de tellers bovenaan zet en de kijkers als smalle lijst rechts.

  Schrijfacties, allemaal bestaande routes met dezelfde afhandeling als de
  schermen waar ze vandaan komen:
  - Scan alle bibliotheken: `scanAll` uit activity.ts, zoals scherm 25.
  - Afbreken en Nu opnieuw bij een taak: `POST /jobs/{id}/cancel` en `/retry`.
  - Stoppen bij een omzetsessie: `DELETE /transcode-sessions/{id}`, achter de
    bevestiging van scherm 37.
  Na elke actie leest het overzicht alles opnieuw via `onreload`.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { adminApi } from '../api/admin';
  import { adminSettingsApi } from '../api/adminSettings';
  import { ApiError } from '../api/errors';
  import type { Job } from '../api/types';
  import { t } from '../i18n';
  import { formatRelative } from '../util/format';
  import { session } from '../stores/session.svelte';
  import { scanAll as scanAllLibraries } from './activity';
  import ActivityPanel from './ActivityPanel.svelte';
  import LibraryProblemAlert from './LibraryProblemAlert.svelte';
  import type { LibraryProblem } from './libraryErrors';
  import { opsProblem } from './opsErrors';
  import OverviewTiles from './OverviewTiles.svelte';
  import ServerPanel from './ServerPanel.svelte';
  import { transcodeProblem } from './transcode/transcodeErrors';
  import WatchingPanel from './WatchingPanel.svelte';
  import { storageSummary, type OverviewData } from './overview';

  interface Props {
    data: OverviewData;
    /** Leest het overzicht opnieuw; komt van OverviewLoader. */
    onreload?: () => void;
  }

  let { data, onreload = () => {} }: Props = $props();

  const ready = $derived(data.server.health?.ready !== false);
  const status = $derived(
    t(ready ? 'admin.status.online' : 'admin.status.notReady', {
      version: data.server.version,
      since: formatRelative(data.server.started_at) ?? ''
    })
  );
  const unmounted = $derived(storageSummary(data.roots).unmounted);

  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  let scanning = $state(false);
  let stopping = $state<Record<string, boolean>>({});
  let retrying = $state<Record<string, boolean>>({});
  let stopTarget = $state<{ id: string; name: string } | null>(null);
  let stopOpen = $state(false);

  function reload(): void {
    problem = null;
    onreload();
  }

  function fail(found: LibraryProblem, again: () => void): void {
    notice = null;
    problem = found;
    retry = again;
  }

  async function scanAll(): Promise<void> {
    problem = null;
    notice = null;
    scanning = true;
    const { message, firstError } = await scanAllLibraries(adminApi(session.client), data);
    scanning = false;
    if (firstError) fail(opsProblem(firstError.err, firstError.library.title), () => void scanAll());
    // Na `fail`, dat de melding wist: wat wel lukte hoort er ook bij te staan.
    notice = message;
    onreload();
  }

  async function stopJob(job: Job, name: string): Promise<void> {
    problem = null;
    stopping[job.id] = true;
    try {
      await adminApi(session.client).cancelJob(job.id);
      notice = t('admin.act.notice.cancelRequested', { name });
      onreload();
    } catch (err) {
      fail(opsProblem(err, name), () => void stopJob(job, name));
      // Een afgeronde job (409, reden `finished`) is oud nieuws: toon de echte stand.
      if (err instanceof ApiError) onreload();
    } finally {
      stopping[job.id] = false;
    }
  }

  async function retryJob(job: Job, name: string): Promise<void> {
    problem = null;
    retrying[job.id] = true;
    try {
      await adminApi(session.client).retryJob(job.id);
      notice = t('admin.act.notice.retried', { name });
      onreload();
    } catch (err) {
      fail(opsProblem(err, name), () => void retryJob(job, name));
    } finally {
      retrying[job.id] = false;
    }
  }

  function askStopSession(id: string, name: string): void {
    stopTarget = { id, name };
    stopOpen = true;
  }

  // Het doel gaat als argument mee: "Opnieuw proberen" mag nooit de sessie
  // raken die de beheerder daarna heeft aangeklikt en weer geannuleerd.
  async function stopSession(target = stopTarget): Promise<void> {
    if (!target) return;
    const { id, name } = target;
    stopping[id] = true;
    problem = null;
    try {
      await adminSettingsApi(session.client).stopTranscodeSession(id);
      stopOpen = false;
      notice = t('admin.act.notice.sessionStopped', { name });
      onreload();
    } catch (err) {
      stopOpen = false;
      fail(transcodeProblem(err, 'stop', name), () => void stopSession({ id, name }));
      // De sessie bestaat niet meer: toon de echte stand.
      if (err instanceof ApiError && err.status === 404) onreload();
    } finally {
      stopping[id] = false;
    }
  }
</script>

<header class="head">
  <p class="crumb">{t('admin.title')}</p>
  <div class="title-row">
    <div class="name">
      <h1 class="title">{data.server.name}</h1>
      <StatusPill variant="dot" tone={ready ? 'ok' : 'warn'} label={status} />
    </div>
    <button
      type="button"
      class="btn btn--secondary btn--sm scan-all"
      disabled={scanning || data.libraries.length === 0}
      onclick={() => void scanAll()}
    >
      <AdminIcon name="scan" size={16} />{scanning ? t('admin.act.scanAll.busy') : t('admin.overview.scanAll')}
    </button>
  </div>
</header>

{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}
{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={reload} />
  </div>
{/if}

{#if unmounted.length > 0}
  <div class="msg">
    <Alert tone="warn" title={t('admin.alert.unmountedTitle')} live={false}>
      {#if unmounted.length === 1}
        {t('admin.alert.unmountedBody', { path: unmounted[0]!.path })}
      {:else}
        {t('admin.alert.unmountedMany', { count: unmounted.length })}
      {/if}
      {#snippet actions()}
        <a class="btn btn--secondary btn--sm" href="/admin/storage">{t('admin.alert.action')}</a>
      {/snippet}
    </Alert>
  </div>
{/if}

<div class="stack">
  <WatchingPanel {data} {stopping} onstop={askStopSession} />

  <div class="cols">
    <ActivityPanel
      {data}
      {stopping}
      {retrying}
      onstop={(job, name) => void stopJob(job, name)}
      onretry={(job, name) => void retryJob(job, name)}
    />
    <ServerPanel {data} info={session.info} />
  </div>

  <OverviewTiles {data} />
</div>

<ConfirmDialog
  bind:open={stopOpen}
  busy={stopTarget ? stopping[stopTarget.id] : false}
  danger={false}
  title={t('admin.media.transcode.stopTitle')}
  message={t('admin.media.transcode.stopBody', { name: stopTarget?.name ?? '' })}
  confirmLabel={t('admin.media.transcode.stop')}
  onconfirm={() => void stopSession()}
/>

<style>
  .head {
    margin-bottom: 18px;
  }

  .crumb {
    margin: 0 0 4px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .title-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px 16px;
  }

  .name {
    display: grid;
    gap: 8px;
    min-width: 0;
  }

  /* Op 320 past "Online · versie … · gestart …" niet op één regel; de pil
     mag hier afbreken in plaats van de pagina breder te maken. */
  .name :global(.pill) {
    min-width: 0;
    white-space: normal;
  }

  .title {
    min-width: 0;
    margin: 0;
    font-size: 34px;
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .msg {
    margin-bottom: 16px;
  }

  .stack {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 20px;
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
    align-items: start;
    gap: 14px;
  }

  @media (max-width: 1199px) {
    .cols {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  /* Onder 900 de knop over de volle breedte, zoals scherm 25 hem tekent. */
  @media (max-width: 899px) {
    .title {
      font-size: 26px;
    }

    .title-row {
      flex-direction: column;
      align-items: stretch;
    }

    .scan-all {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
