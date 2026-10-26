<!--
  Serverbeheer, transcode-sessies (northstar 37, S18.5): wie nu omgezet wordt,
  met welke hardware, en Stoppen per sessie.

  Verversen: zolang er sessies lopen leest de pagina elke vijf seconden
  opnieuw; bij een lege lijst houdt hij op, zodat een rustige server geen
  verkeer maakt (zoals scherm 25). Een mislukte verversing laat de staande
  lijst staan en stopt het verversen tot de bezoeker kiest.

  Schrijfactie: `DELETE /transcode-sessions/{id}`, altijd achter een
  bevestiging die zegt dat de kijker onderbroken wordt (dezelfde als op
  scherm 28). Een weigering laat de lijst intact; alleen "bestaat niet meer"
  (404) leest de lijst opnieuw, want dan is de lijst verouderd.

  Niet gebouwd omdat het contract het niet draagt, zie transcode.ts: titel en
  toestel per sessie, voortgang en snelheid, de omzetting zelf, de
  transcodemap en "Vandaag afgelopen". De instellingen (maximum, hardware)
  zijn omgevingsvariabelen en staan alleen-lezen op scherm 28.
-->
<script lang="ts">
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Alert from '../../components/Alert.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { adminApi } from '../../api/admin';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError, describeError } from '../../api/errors';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import TranscodeTable from './TranscodeTable.svelte';
  import TranscodeTiles from './TranscodeTiles.svelte';
  import { transcodeProblem } from './transcodeErrors';
  import {
    TRANSCODE_POLL_MS,
    atMaximum,
    isLive,
    loadTranscode,
    sortedSessions,
    type TranscodeData
  } from './transcode';

  let data = $state<TranscodeData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let tick = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let stopping = $state<Record<string, boolean>>({});
  let stopTarget = $state<{ id: string; name: string } | null>(null);
  let stopOpen = $state(false);
  /** Na een mislukte verversing wacht de pagina op de bezoeker. */
  let paused = $state(false);

  const transcodeOn = $derived(session.info?.capabilities.transcode === true);

  $effect(() => {
    void attempt;
    void tick;
    const controller = new AbortController();
    loadTranscode(adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
        paused = false;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        if (data) {
          paused = true;
          problem = transcodeProblem(err, 'list');
          retry = refresh;
        } else {
          failure = describeError(err);
        }
      });
    return () => controller.abort();
  });

  // Elke nieuwe stand zet de timer opnieuw, dus er loopt nooit meer dan één.
  $effect(() => {
    if (!data || paused || !isLive(data)) return;
    const timer = setTimeout(() => (tick += 1), TRANSCODE_POLL_MS);
    return () => clearTimeout(timer);
  });

  const items = $derived(data ? sortedSessions(data.list.items) : []);

  function refresh(): void {
    problem = null;
    tick += 1;
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
      tick += 1;
    } catch (err) {
      stopOpen = false;
      problem = transcodeProblem(err, 'stop', name);
      retry = () => void stop();
      // De sessie bestaat niet meer: toon de echte stand. Verder blijft de lijst zoals hij was.
      if (err instanceof ApiError && err.status === 404) tick += 1;
    } finally {
      stopping[id] = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.tc.title')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.media'), href: '/admin/media' },
    { label: t('admin.tc.title') }
  ]}
>
  {#snippet actions()}
    <button type="button" class="btn btn--secondary btn--sm refresh" onclick={refresh}>
      <AdminIcon name="refresh" size={16} />{t('admin.tc.refresh')}
    </button>
  {/snippet}
</AdminPageHead>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={refresh} />
  </div>
{/if}

{#if data}
  <div class="stack">
    <TranscodeTiles list={data.list} />
    {#if !transcodeOn}
      <Alert tone="info" title={t('admin.tc.off.title')}>
        {t('admin.tc.off.body')}
        {#snippet actions()}
          <a class="btn btn--secondary btn--sm" href="/admin/media">{t('admin.nav.media')}</a>
        {/snippet}
      </Alert>
    {:else}
      {#if atMaximum(data.list)}
        <Alert tone="warn" title={t('admin.tc.full.title')}>
          {t('admin.tc.full.body')}
          {#snippet actions()}
            <a class="btn btn--secondary btn--sm" href="/admin/media">{t('admin.tc.full.action')}</a>
          {/snippet}
        </Alert>
      {/if}
      <TranscodeTable {items} users={data.users} {stopping} onstop={askStop} />
    {/if}
  </div>

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

  .stack {
    display: grid;
    gap: 16px;
  }

  /* Onder 900 over de volle breedte, zoals 37@393 de knop tekent. */
  @media (max-width: 899px) {
    .refresh {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
