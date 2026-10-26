<!--
  Serverbeheer, bibliotheken (northstar 21): kop met Bibliotheek toevoegen, de
  tabel, en een toelichting zodra er nog een bibliotheek uit
  PLEYA_SERVER_LIBRARIES komt. Scannen start hier (`POST /libraries/{id}/scan`);
  zolang een scan wacht of loopt vraagt de pagina elke paar seconden de stand
  van die ene bibliotheek opnieuw op. Overnemen in beheer vraagt eerst om
  bevestiging, omdat het niet terug te draaien is.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import type { Library } from '../api/types';
  import { describeError } from '../api/errors';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import LibrariesTable from './LibrariesTable.svelte';
  import LibraryProblemAlert from './LibraryProblemAlert.svelte';
  import {
    SCAN_POLL_MS,
    isConfigManaged,
    loadLibraries,
    scanActive,
    type LibrariesData
  } from './libraries';
  import { libraryProblem, type LibraryProblem } from './libraryErrors';

  interface Props {
    /** Titel van een bibliotheek die net verwijderd is (`?removed=`). */
    removed?: string | null;
    /** Titel van een bibliotheek die net aangemaakt is (`?added=`). */
    added?: string | null;
  }

  let { removed = null, added = null }: Props = $props();

  const api = $derived(adminApi(session.client));

  let data = $state<LibrariesData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<(() => void) | null>(null);
  let notice = $state<string | null>(null);
  let starting = $state<Record<string, boolean>>({});
  let pollTick = $state(0);

  let adoptTarget = $state<Library | null>(null);
  let adoptOpen = $state(false);
  let adoptBusy = $state(false);

  $effect(() => {
    if (removed) notice = t('admin.lib.notice.removed', { name: removed });
    else if (added) notice = t('admin.lib.notice.added', { name: added });
  });

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    failure = null;
    loadLibraries(session.client, adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        failure = describeError(err);
      });
    return () => controller.abort();
  });

  const activeIds = $derived(
    data ? data.libraries.filter((l) => scanActive(data!.scans[l.id])).map((l) => l.id) : []
  );

  // Volgt alleen de bibliotheken met een wachtende of lopende scan. Faalt een
  // ronde, dan probeert de volgende het gewoon opnieuw (`pollTick`).
  $effect(() => {
    void pollTick;
    const ids = activeIds;
    if (ids.length === 0) return;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      void Promise.all(ids.map((id) => api.lastScan(id, controller.signal)))
        .then((scans) => {
          if (!data) return;
          ids.forEach((id, i) => (data!.scans[id] = scans[i] ?? null));
        })
        .catch(() => {})
        .finally(() => {
          if (!controller.signal.aborted) pollTick += 1;
        });
    }, SCAN_POLL_MS);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  });

  const envManaged = $derived(data ? data.libraries.filter(isConfigManaged) : []);

  function fail(err: unknown, name: string, again: () => void): void {
    notice = null;
    problem = libraryProblem(err, name);
    retry = again;
  }

  async function scan(library: Library): Promise<void> {
    problem = null;
    starting[library.id] = true;
    try {
      const started = await api.startScan(library.id);
      if (data) data.scans[library.id] = started;
      notice = t('admin.lib.notice.scanQueued', { name: library.title });
    } catch (err) {
      fail(err, library.title, () => void scan(library));
    } finally {
      starting[library.id] = false;
    }
  }

  function askAdopt(library: Library): void {
    adoptTarget = library;
    adoptOpen = true;
  }

  async function adopt(): Promise<void> {
    const library = adoptTarget;
    if (!library) return;
    problem = null;
    adoptBusy = true;
    try {
      const adopted = await api.adoptLibrary(library.id);
      if (data) data.libraries = data.libraries.map((l) => (l.id === adopted.id ? adopted : l));
      notice = t('admin.lib.notice.adopted', { name: adopted.title });
    } catch (err) {
      fail(err, library.title, () => askAdopt(library));
    } finally {
      adoptBusy = false;
      adoptOpen = false;
    }
  }

  function reload(): void {
    problem = null;
    attempt += 1;
  }
</script>

<AdminPageHead
  title={t('admin.nav.libraries')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.libraries') }]}
>
  {#snippet actions()}
    <a class="btn btn--sm" href="/admin/libraries/new">
      <AdminIcon name="plus" size={16} />{t('admin.lib.action.add')}
    </a>
  {/snippet}
</AdminPageHead>

{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}
{#if problem}
  <div class="msg">
    <LibraryProblemAlert
      {problem}
      onretry={() => retry?.()}
      onreload={reload}
      onadopt={() => retry?.()}
    />
  </div>
{/if}

{#if data}
  {#if data.libraries.length === 0}
    <StateView title={t('admin.lib.empty.title')} message={t('admin.lib.empty.body')}>
      {#snippet actions()}
        <a class="btn btn--sm" href="/admin/libraries/new">{t('admin.lib.action.add')}</a>
      {/snippet}
    </StateView>
  {:else}
    <LibrariesTable {data} {starting} onscan={(l) => void scan(l)} onadopt={askAdopt} />
  {/if}

  {#if envManaged.length > 0}
    <div class="note">
      <Alert
        tone="info"
        live={false}
        title={envManaged.length === 1
          ? t('admin.lib.envNote.single', { name: envManaged[0]!.title })
          : t('admin.lib.envNote.many', { count: envManaged.length })}
      >
        {t('admin.lib.envNote.before')}
        <span class="mono">PLEYA_SERVER_LIBRARIES</span>
        {t('admin.lib.envNote.after')}
      </Alert>
    </div>
  {/if}
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

<ConfirmDialog
  bind:open={adoptOpen}
  danger={false}
  busy={adoptBusy}
  title={t('admin.lib.adopt.title', { name: adoptTarget?.title ?? '' })}
  message={t('admin.lib.adopt.body', { name: adoptTarget?.title ?? '' })}
  confirmLabel={t('admin.lib.adopt.confirm')}
  onconfirm={() => void adopt()}
/>

<style>
  .msg {
    margin-bottom: 14px;
  }

  .note {
    margin-top: 16px;
  }
</style>
