<!--
  Serverbeheer, scans en taken (northstar 25): wat er nu loopt, wat mislukt is
  en de geschiedenis van de scans. Zolang er iets loopt of nu aan de beurt is
  leest de pagina elke vijf seconden opnieuw; daarna houdt hij op, zodat een
  rustige server geen verkeer maakt.

  Schrijfacties, en wat elk vraagt:
  - Alles scannen: `POST /libraries/{id}/scan` per bibliotheek. Een bibliotheek
    met een niet-gemounte root wordt overgeslagen, en een scan die al wacht of
    loopt (409) telt als "stond al in de wachtrij" en niet als fout.
  - Afbreken: `POST /jobs/{id}/cancel` op de job van de scan. De server stopt
    een lopende job op het eerstvolgende veilige punt.
  - Nu opnieuw: `POST /jobs/{id}/retry`.
  Geen van drie vraagt een bevestiging: de northstar tekent er geen, en geen
  van de drie vernietigt iets dat niet terug te halen is (een afgebroken scan
  begint bij de volgende ronde opnieuw).
-->
<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import AdminIcon from '../components/AdminIcon.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import { ApiError, describeError } from '../api/errors';
  import type { Job, Library, Scan } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import ActivityFailures from './ActivityFailures.svelte';
  import ActivityHistory from './ActivityHistory.svelte';
  import ActivityRunning from './ActivityRunning.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import LibraryProblemAlert from './LibraryProblemAlert.svelte';
  import {
    ACTIVITY_POLL_MS,
    failureItems,
    historyRows,
    isLive,
    loadActivity,
    planScanAll,
    runningItems,
    type ActivityData
  } from './activity';
  import type { LibraryProblem } from './libraryErrors';
  import { opsProblem } from './opsErrors';

  const api = $derived(adminApi(session.client));

  let data = $state<ActivityData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let tick = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  let scanning = $state(false);
  let stopping = $state<Record<string, boolean>>({});
  let retrying = $state<Record<string, boolean>>({});

  // Oudere pagina's scans, los van de eerste: een verversing leest alleen de eerste.
  let older = $state<Scan[]>([]);
  let olderCursor = $state<string | null | undefined>(undefined);
  let loadingMore = $state(false);

  $effect(() => {
    void attempt;
    void tick;
    const controller = new AbortController();
    loadActivity(session.client, adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        if (data) {
          // De staande lijst blijft staan; het verversen stopt tot de bezoeker kiest.
          problem = opsProblem(err, t('admin.nav.activity'));
          retry = refresh;
        } else {
          failure = describeError(err);
        }
      });
    return () => controller.abort();
  });

  // Elke nieuwe stand zet de timer opnieuw, dus er loopt nooit meer dan één.
  $effect(() => {
    if (!data || !isLive(data)) return;
    const timer = setTimeout(() => (tick += 1), ACTIVITY_POLL_MS);
    return () => clearTimeout(timer);
  });

  const now = $derived.by(() => {
    void data;
    return Date.now();
  });
  const running = $derived(data ? runningItems(data) : []);
  const failures = $derived(data ? failureItems(data) : []);
  const rows = $derived(data ? historyRows([...data.scans, ...older], data.libraries, now) : []);
  const moreCursor = $derived(older.length > 0 || olderCursor !== undefined ? olderCursor : data?.next);

  function refresh(): void {
    problem = null;
    tick += 1;
  }

  function reload(): void {
    problem = null;
    older = [];
    olderCursor = undefined;
    attempt += 1;
  }

  function fail(err: unknown, name: string, again: () => void): void {
    notice = null;
    problem = opsProblem(err, name);
    retry = again;
  }

  async function more(): Promise<void> {
    const cursor = moreCursor;
    if (!cursor) return;
    problem = null;
    loadingMore = true;
    try {
      const page = await api.scansPage(20, cursor);
      older = [...older, ...page.items];
      olderCursor = page.nextCursor;
    } catch (err) {
      fail(err, t('admin.act.history.title'), () => void more());
    } finally {
      loadingMore = false;
    }
  }

  async function scanAll(): Promise<void> {
    if (!data) return;
    problem = null;
    notice = null;
    scanning = true;
    const plan = planScanAll(data);
    let queued = 0;
    let already = plan.running.length;
    let firstError: { err: unknown; library: Library } | null = null;
    const results = await Promise.allSettled(plan.start.map((l) => api.startScan(l.id)));
    for (const [i, result] of results.entries()) {
      if (result.status === 'fulfilled') queued += 1;
      else if (result.reason instanceof ApiError && result.reason.code === 'library.scan_in_progress')
        already += 1;
      else if (!firstError) firstError = { err: result.reason, library: plan.start[i]! };
    }
    scanning = false;
    const parts = [t('admin.act.scanAll.result', { queued })];
    if (already > 0) parts.push(t('admin.act.scanAll.running', { count: already }));
    if (plan.skipped.length > 0) parts.push(t('admin.act.scanAll.skipped', { count: plan.skipped.length }));
    if (firstError) {
      const { err, library } = firstError;
      fail(err, library.title, () => void scanAll());
    }
    // Na `fail`, dat de melding wist: wat wel lukte hoort er ook bij te staan.
    notice = parts.join(' ');
    // Ook bij een gedeeltelijke mislukking: wat wel in de wachtrij staat moet zichtbaar zijn.
    tick += 1;
  }

  async function stop(job: Job, name: string): Promise<void> {
    problem = null;
    stopping[job.id] = true;
    try {
      await api.cancelJob(job.id);
      notice = t('admin.act.notice.cancelRequested', { name });
      tick += 1;
    } catch (err) {
      fail(err, name, () => void stop(job, name));
      // Een afgeronde job (409, reden `finished`) is oud nieuws: toon de echte stand.
      if (err instanceof ApiError) tick += 1;
    } finally {
      stopping[job.id] = false;
    }
  }

  async function retryJob(job: Job, name: string): Promise<void> {
    problem = null;
    retrying[job.id] = true;
    try {
      await api.retryJob(job.id);
      notice = t('admin.act.notice.retried', { name });
      tick += 1;
    } catch (err) {
      fail(err, name, () => void retryJob(job, name));
    } finally {
      retrying[job.id] = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.nav.activity')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.activity') }]}
>
  {#snippet actions()}
    <button
      type="button"
      class="btn btn--secondary btn--sm scan-all"
      disabled={scanning || !data || data.libraries.length === 0}
      onclick={() => void scanAll()}
    >
      <AdminIcon name="scan" size={16} />{scanning ? t('admin.act.scanAll.busy') : t('admin.act.scanAll')}
    </button>
  {/snippet}
</AdminPageHead>

{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}
{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={reload} />
  </div>
{/if}

{#if data}
  <div class="stack">
    <ActivityRunning items={running} {now} {stopping} onstop={(j, n) => void stop(j, n)} />
    <ActivityFailures items={failures} {retrying} onretry={(j, n) => void retryJob(j, n)} />
    <ActivityHistory {rows} more={Boolean(moreCursor)} {loadingMore} onmore={() => void more()} />
  </div>
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

  /* Onder 900 over de volle breedte, zoals 25@393 de knop tekent. */
  @media (max-width: 899px) {
    .scan-all {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
