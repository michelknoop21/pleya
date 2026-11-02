<script lang="ts">
  import { adminApi } from '../api/admin';
  import { describeError } from '../api/errors';
  import type { ArtworkCacheStats, Job } from '../api/types';
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Panel from '../components/Panel.svelte';
  import { t, plural } from '../i18n';
  import { session } from '../stores/session.svelte';
  import { formatBytes } from '../util/format';
  import { RECHECK_REFRESH_MS } from './storage';

  const allowed = $derived(session.canAdminister === true && session.capabilities?.artwork_cache_admin === true);
  let stats = $state<ArtworkCacheStats | null>(null);
  let failure = $state<string | null>(null);
  let monitorFailure = $state(false);
  let notice = $state<'accepted' | 'succeeded' | null>(null);
  let jobState = $state<string | null>(null);
  let confirming = $state(false);
  let writing = $state(false);
  let loading = $state(false);
  let refresh = $state<() => void>(() => {});
  let enqueue = $state<() => Promise<void>>(async () => {});
  let sequence = 0;

  $effect(() => {
    const client = session.client;
    const generation = client.sessionGeneration;
    const subject = session.me?.id;
    const enabled = allowed;
    const own = ++sequence;
    const controller = new AbortController();
    const api = adminApi(client);
    let timer: ReturnType<typeof setTimeout> | undefined;
    let previous = new Map<string, string>();
    let latest: Job[] = [];
    let baseline = new Set<string>();
    let awaiting = false;
    let statsSequence = 0;
    let jobsSequence = 0;
    const current = () => !controller.signal.aborted && own === sequence && enabled && allowed &&
      client === session.client && generation === client.sessionGeneration && subject === session.me?.id;
    stats = null; failure = null; monitorFailure = false; notice = null;
    jobState = null; confirming = false; writing = false; loading = false;

    async function readStats(): Promise<void> {
      if (!current()) return;
      const read = ++statsSequence;
      loading = true;
      try {
        const result = await api.artworkCacheStats(controller.signal);
        if (!current() || read !== statsSequence) return;
        stats = result; failure = null;
      } catch (error) {
        if (current() && read === statsSequence) failure = describeError(error);
      } finally {
        if (current() && read === statsSequence) loading = false;
      }
    }
    async function readJobs(): Promise<void> {
      const read = ++jobsSequence;
      try {
        const jobs = (await api.jobs(50, controller.signal)).filter(j => j.kind === 'artwork_cache_purge');
        if (!current() || read !== jobsSequence) return;
        monitorFailure = false;
        const succeeded = jobs.some(j => j.state === 'succeeded' &&
          (previous.get(j.id) === 'pending' || previous.get(j.id) === 'running' || (awaiting && !baseline.has(j.id))));
        latest = jobs;
        previous = new Map(jobs.map(j => [j.id, j.state]));
        jobState = jobs[0]?.state ?? null;
        if (succeeded) {
          awaiting = false;
          await readStats();
          if (current() && read === jobsSequence) notice = 'succeeded';
        }
      } catch {
        if (current() && read === jobsSequence) monitorFailure = true;
      }
    }
    async function poll(): Promise<void> {
      await readJobs();
      if (current()) timer = setTimeout(() => void poll(), RECHECK_REFRESH_MS);
    }
    refresh = () => { if (current()) { notice = null; void readStats(); void readJobs(); } };
    enqueue = async () => {
      if (!current() || writing || !confirming) return;
      writing = true; failure = null; notice = null;
      baseline = new Set(latest.map(j => j.id));
      try {
        await api.purgeArtworkCache(controller.signal);
        if (!current()) return;
        confirming = false;
        notice = 'accepted'; awaiting = true;
        await readJobs();
      } catch (error) {
        if (current()) { confirming = false; failure = describeError(error); }
      } finally {
        if (current()) writing = false;
      }
    };
    if (enabled) { void readStats(); void poll(); }
    return () => { controller.abort(); clearTimeout(timer); };
  });
</script>

{#if allowed}
  <div class="cache">
    <Panel level={2}>
      {#snippet title()}{t('admin.sto.cache.title')}{/snippet}
      {#snippet actions()}
        <button type="button" class="btn btn--ghost btn--sm" disabled={loading} onclick={() => refresh()}>
          {t('admin.sto.cache.reload')}
        </button>
      {/snippet}
      <div class="content">
        <p>{t('admin.sto.cache.body')}</p>
        {#if stats}
          <p class="summary">{plural('admin.sto.cache.summary', stats.files, { size: formatBytes(stats.bytes) })}</p>
        {:else if loading}<p role="status">{t('admin.sto.cache.loading')}</p>{/if}
        {#if failure}<Alert tone="err">{failure}</Alert>{/if}
        {#if monitorFailure}<Alert tone="err">{t('admin.sto.cache.monitorFailed')}</Alert>{/if}
        {#if notice}<p role="status">{t(notice === 'accepted' ? 'admin.sto.cache.accepted' : 'admin.sto.cache.succeeded')}</p>{/if}
        {#if jobState === 'pending' || jobState === 'running'}<p role="status">{t('admin.sto.cache.running')}</p>
        {:else if jobState === 'failed'}<Alert tone="err">{t('admin.sto.cache.failed')}</Alert>
        {:else if jobState === 'cancelled'}<p role="status">{t('admin.sto.cache.cancelled')}</p>{/if}
        <div class="actions">
          <button type="button" class="btn btn--secondary btn--sm" disabled={writing || loading || !stats || jobState === 'pending' || jobState === 'running'} onclick={() => (confirming = true)}>
            {t('admin.sto.cache.purge')}
          </button>
          <a class="btn btn--ghost btn--sm" href="/admin/activity">{t('admin.sto.cache.activity')}</a>
        </div>
      </div>
    </Panel>
  </div>
  <ConfirmDialog bind:open={confirming} title={t('admin.sto.cache.confirmTitle')} message={t('admin.sto.cache.body')}
    confirmLabel={t('admin.sto.cache.confirm')} busy={writing} onconfirm={() => void enqueue()} />
{/if}

<style>
  .cache { margin-top: 16px; }
  .content { display: grid; gap: 12px; font-size: 13px; line-height: 1.5; color: var(--ink-3); }
  p { margin: 0; }
  .summary { color: var(--ink-2); font-weight: 600; }
  .actions { display: flex; flex-wrap: wrap; gap: 10px; }
</style>
