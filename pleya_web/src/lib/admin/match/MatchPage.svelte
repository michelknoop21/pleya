<!--
  Serverbeheer, match en overrides (northstar 36, S22.6): de titels waar de
  server zelf niet uitkwam, de kandidaten per titel, en daarop twee schrijf-
  acties: een kandidaat of eigen nummer kiezen (`PUT /items/{id}/metadata-match`)
  en de match afwijzen (`DELETE`). Beide gaan eerst langs een bevestiging die
  zegt wat er met de titel gebeurt; zonder bevestiging gaat er niets de deur uit.

  Een weigering van de server laat de lijst staan zoals hij was en toont een
  zin met een uitweg (matchErrors.ts). Alleen "bestaat niet meer" (404) leest
  de lijst opnieuw. Na een gelukte actie leest de pagina de lijst opnieuw,
  want de server haalt een gekozen titel van de lijst.

  Bewust niet gebouwd, want de server kent het nog niet (masterlijst S22.5):
  velden per titel overschrijven met herkomst (provenance), artwork kiezen met
  pin, score en poster per kandidaat, en "Providerronde nu". De knoppen en
  panelen staan er daarom niet, ook niet uitgeschakeld.
-->
<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError, describeError } from '../../api/errors';
  import type { MetadataAttentionList } from '../../api/types';
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Alert from '../../components/Alert.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import AdminColumns from '../settings/AdminColumns.svelte';
  import CandidatePanel from './CandidatePanel.svelte';
  import MatchList from './MatchList.svelte';
  import MatchSide from './MatchSide.svelte';
  import { loadMatch, sortedAttention, titleOf } from './match';
  import { matchProblem } from './matchErrors';

  let { initialItem = null }: { initialItem?: string | null } = $props();

  let data = $state<MetadataAttentionList | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  // De link vanaf scherm 29 zet de beginkeuze; daarna beslist de bezoeker.
  // svelte-ignore state_referenced_locally
  let selected = $state<string | null>(initialItem);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  let busy = $state(false);
  /** De keuze die op een bevestiging wacht. */
  let pending = $state<{ externalId: string; label: string } | null>(null);
  let pickOpen = $state(false);
  let rejectOpen = $state(false);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadMatch(adminSettingsApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        if (data) problem = matchProblem(err, '');
        else failure = describeError(err);
      });
    return () => controller.abort();
  });

  const items = $derived(data ? sortedAttention(data.items) : []);
  // Zonder gekozen titel (of een die niet meer op de lijst staat) valt de keuze op de eerste.
  const current = $derived(items.find((i) => i.item_id === selected) ?? null);
  const gone = $derived(Boolean(data && selected && !current));
  const shown = $derived(current ?? (gone ? null : (items[0] ?? null)));

  function reload(): void {
    problem = null;
    attempt += 1;
  }

  function askPick(externalId: string, label: string): void {
    pending = { externalId, label };
    pickOpen = true;
  }

  async function pick(): Promise<void> {
    if (!shown || !pending) return;
    const { externalId, label } = pending;
    const title = titleOf(shown);
    busy = true;
    problem = null;
    notice = null;
    try {
      await adminSettingsApi(session.client).setMetadataMatch(shown.item_id, externalId);
      pickOpen = false;
      notice = t('admin.match.done.pick', { title, candidate: label });
      selected = null;
      attempt += 1;
    } catch (err) {
      pickOpen = false;
      problem = matchProblem(err, title);
      retry = () => askPick(externalId, label);
      if (err instanceof ApiError && err.status === 404) attempt += 1;
    } finally {
      busy = false;
    }
  }

  async function reject(): Promise<void> {
    if (!shown) return;
    const title = titleOf(shown);
    busy = true;
    problem = null;
    notice = null;
    try {
      await adminSettingsApi(session.client).clearMetadataMatch(shown.item_id);
      rejectOpen = false;
      notice = t('admin.match.done.reject', { title });
      attempt += 1;
    } catch (err) {
      rejectOpen = false;
      problem = matchProblem(err, title);
      retry = () => (rejectOpen = true);
      if (err instanceof ApiError && err.status === 404) attempt += 1;
    } finally {
      busy = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.match.title')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.metadata'), href: '/admin/metadata' },
    { label: t('admin.match.title') }
  ]}
>
  {#snippet actions()}
    <button type="button" class="btn btn--secondary btn--sm refresh" onclick={reload}>
      <AdminIcon name="refresh" size={16} />{t('admin.match.refresh')}
    </button>
  {/snippet}
</AdminPageHead>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={reload} />
  </div>
{/if}
{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}

{#if data}
  <AdminColumns>
    {#snippet left()}
      <MatchList list={data!} {items} selected={shown?.item_id ?? null} onselect={(id) => (selected = id)} />
      {#if gone}
        <Alert tone="info">{t('admin.match.gone')}</Alert>
      {/if}
      {#if shown}
        <CandidatePanel item={shown} {busy} onpick={askPick} onreject={() => (rejectOpen = true)} />
      {/if}
    {/snippet}
    {#snippet right()}
      <MatchSide list={data!} />
    {/snippet}
  </AdminColumns>

  <ConfirmDialog
    bind:open={pickOpen}
    {busy}
    danger={false}
    title={t('admin.match.confirm.pickTitle')}
    message={t('admin.match.confirm.pickBody', {
      title: shown ? titleOf(shown) : '',
      candidate: pending?.label ?? ''
    })}
    confirmLabel={t('admin.match.confirm.pick')}
    onconfirm={() => void pick()}
  />
  <ConfirmDialog
    bind:open={rejectOpen}
    {busy}
    title={t('admin.match.confirm.rejectTitle')}
    message={t('admin.match.confirm.rejectBody', { title: shown ? titleOf(shown) : '' })}
    confirmLabel={t('admin.match.confirm.reject')}
    onconfirm={() => void reject()}
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

  @media (max-width: 899px) {
    .refresh {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
