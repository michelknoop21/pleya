<!--
  Scherm 22: een bibliotheek bewerken (`PATCH /libraries/{id}`) of toevoegen
  (`POST /libraries`), met Stand en Verwijderen rechts (2fr 1fr vanaf 1200,
  daaronder één kolom).

  Een bibliotheek uit PLEYA_SERVER_LIBRARIES (`managed: config`) is hier alleen
  te lezen: de server weigert elke wijziging en elke verwijdering met
  `library.config_managed`. De uitweg die het contract wel kent is overnemen
  in beheer (`POST /libraries/{id}/adopt`); daarna is alles te wijzigen.

  Opslaan stuurt alleen wat veranderd is. Metadata verversen en het paneel
  Toegang uit de northstar staan er niet: daar is geen route voor (er is geen
  verversroute, en de rechten van een gebruiker zijn alleen te schrijven).
-->
<script lang="ts">
  import { goto } from '$app/navigation';

  import AdminIcon from '../components/AdminIcon.svelte';
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import { describeError } from '../api/errors';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import LibraryDeletePanel from './LibraryDeletePanel.svelte';
  import LibraryProblemAlert from './LibraryProblemAlert.svelte';
  import LibraryRootsPanel from './LibraryRootsPanel.svelte';
  import LibrarySettingsPanel from './LibrarySettingsPanel.svelte';
  import LibraryStatusPanel from './LibraryStatusPanel.svelte';
  import {
    createBody,
    emptyForm,
    formFromLibrary,
    formValid,
    isConfigManaged,
    loadLibraryDetail,
    scanActive,
    updateBody,
    type LibraryDetail,
    type LibraryForm
  } from './libraries';
  import { libraryProblem, type LibraryProblem } from './libraryErrors';

  /** Null is een nieuwe bibliotheek (`/admin/libraries/new`). */
  let { id }: { id: string | null } = $props();

  const api = $derived(adminApi(session.client));
  const LIST = '/admin/libraries';
  const uid = $props.id();
  const formId = `${uid}-form`;

  let detail = $state<LibraryDetail | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let original = $state<LibraryForm>(emptyForm());
  let form = $state<LibraryForm>(emptyForm());

  let saving = $state(false);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<(() => void) | null>(null);
  let notice = $state<string | null>(null);
  let deleteOpen = $state(false);
  let deleting = $state(false);
  let adoptOpen = $state(false);
  let adopting = $state(false);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    failure = null;
    loadLibraryDetail(session.client, adminApi(session.client), id, controller.signal)
      .then((result) => {
        detail = result;
        original = result.library ? formFromLibrary(result.library, result.roots) : emptyForm();
        form = { ...original, roots: [...original.roots] };
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        failure = describeError(err);
      });
    return () => controller.abort();
  });

  const library = $derived(detail?.library ?? null);
  const creating = $derived(id === null);
  const readonly = $derived(library !== null && isConfigManaged(library));
  const changes = $derived(updateBody(original, form));
  const dirty = $derived(creating || Object.keys(changes).length > 0);
  const canSave = $derived(!readonly && !saving && dirty && formValid(form));
  const name = $derived(library?.title ?? form.title.trim());

  function fail(err: unknown, again: () => void): void {
    notice = null;
    problem = libraryProblem(err, name);
    retry = again;
  }

  function reload(): void {
    problem = null;
    notice = null;
    attempt += 1;
  }

  async function save(event?: SubmitEvent): Promise<void> {
    event?.preventDefault();
    if (!canSave) return;
    problem = null;
    saving = true;
    try {
      if (creating) {
        const created = await api.createLibrary(createBody(form));
        await goto(`${LIST}?added=${encodeURIComponent(created.title)}`);
        return;
      }
      if (!library) return;
      const updated = await api.updateLibrary(library.id, changes);
      const roots = await api.storageRoots();
      detail = { ...detail!, library: updated, roots };
      original = formFromLibrary(updated, roots);
      form = { ...original, roots: [...original.roots] };
      notice = t('admin.lib.notice.saved', { name: updated.title });
    } catch (err) {
      fail(err, () => void save());
    } finally {
      saving = false;
    }
  }

  async function scan(): Promise<void> {
    if (!library) return;
    problem = null;
    try {
      const started = await api.startScan(library.id);
      detail = { ...detail!, scan: started };
      notice = t('admin.lib.notice.scanQueued', { name: library.title });
    } catch (err) {
      fail(err, () => void scan());
    }
  }

  async function remove(): Promise<void> {
    if (!library) return;
    problem = null;
    deleting = true;
    try {
      await api.deleteLibrary(library.id, library.title);
      deleteOpen = false;
      await goto(`${LIST}?removed=${encodeURIComponent(library.title)}`);
    } catch (err) {
      deleteOpen = false;
      fail(err, () => (deleteOpen = true));
    } finally {
      deleting = false;
    }
  }

  async function adopt(): Promise<void> {
    if (!library) return;
    problem = null;
    adopting = true;
    try {
      const adopted = await api.adoptLibrary(library.id);
      detail = { ...detail!, library: adopted };
      notice = t('admin.lib.notice.adopted', { name: adopted.title });
    } catch (err) {
      fail(err, () => (adoptOpen = true));
    } finally {
      adopting = false;
      adoptOpen = false;
    }
  }
</script>

{#if detail && (creating || library)}
  <AdminPageHead
    title={library ? library.title : t('admin.lib.action.add')}
    crumbs={[
      { label: t('admin.title'), href: '/admin' },
      { label: t('admin.nav.libraries'), href: LIST },
      { label: library ? library.title : t('admin.lib.new') }
    ]}
  >
    {#snippet actions()}
      {#if library}
        <button
          type="button"
          class="btn btn--ghost btn--sm"
          disabled={scanActive(detail?.scan)}
          onclick={() => void scan()}
        >
          <AdminIcon name="scan" size={16} />{t('admin.lib.action.scanNow')}
        </button>
      {/if}
    {/snippet}
  </AdminPageHead>

  {#if readonly && library}
    <div class="msg">
      <Alert tone="info" live={false} title={t('admin.lib.envNote.single', { name: library.title })}>
        {t('admin.lib.readonly')}
        {#snippet actions()}
          <button type="button" class="btn btn--secondary btn--sm" onclick={() => (adoptOpen = true)}>
            {t('admin.lib.action.adopt')}
          </button>
        {/snippet}
      </Alert>
    </div>
  {/if}
  {#if notice}
    <div class="msg"><Alert tone="info">{notice}</Alert></div>
  {/if}
  {#if problem}
    <div class="msg">
      <LibraryProblemAlert
        {problem}
        onretry={() => retry?.()}
        onreload={reload}
        onadopt={() => (adoptOpen = true)}
      />
    </div>
  {/if}

  <!-- Het formulier omvat alleen de linkerkolom: Verwijderen rechts heeft zijn
       eigen formulier in de dialoog, en formulieren nesten mag niet. -->
  <div class="cols" class:cols--single={!library}>
    <form class="main" id={formId} onsubmit={(e) => void save(e)}>
      <LibrarySettingsPanel
        bind:form
        currentKind={library?.kind ?? null}
        itemCount={library?.item_count ?? 0}
        {readonly}
      />
      <LibraryRootsPanel
        roots={detail.roots}
        bind:selected={form.roots}
        libraryId={library?.id ?? null}
        {readonly}
      />
    </form>
    {#if library}
      <div class="side">
        <LibraryStatusPanel {library} scan={detail.scan} coverage={detail.coverage} />
        {#if !readonly}
          <LibraryDeletePanel
            {library}
            busy={deleting}
            bind:open={deleteOpen}
            onconfirm={() => void remove()}
          />
        {/if}
      </div>
    {/if}
    <div class="foot">
      <a class="btn btn--ghost" href={LIST}>{t('dialog.cancel')}</a>
      {#if !readonly}
        <button
          type="submit"
          form={formId}
          class="btn"
          disabled={!canSave}
          aria-busy={saving ? 'true' : undefined}
        >
          {creating ? t('admin.lib.form.create') : t('admin.lib.form.save')}
        </button>
      {/if}
    </div>
  </div>
{:else if detail?.missing}
  <StateView kind="error" title={t('admin.lib.missing.title')} message={t('admin.lib.missing.body')}>
    {#snippet actions()}
      <a class="btn btn--secondary btn--sm" href={LIST}>{t('admin.lib.action.toList')}</a>
    {/snippet}
  </StateView>
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

{#if library}
  <ConfirmDialog
    bind:open={adoptOpen}
    danger={false}
    busy={adopting}
    title={t('admin.lib.adopt.title', { name: library.title })}
    message={t('admin.lib.adopt.body', { name: library.title })}
    confirmLabel={t('admin.lib.adopt.confirm')}
    onconfirm={() => void adopt()}
  />
{/if}

<style>
  .msg {
    margin-bottom: 14px;
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
    align-items: start;
    gap: 14px;
  }

  .cols--single {
    grid-template-columns: minmax(0, 1fr);
    max-width: 760px;
  }

  .main,
  .side {
    display: grid;
    gap: 14px;
    min-width: 0;
  }

  .foot {
    grid-column: 1 / -1;
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 6px;
  }

  @media (max-width: 1199px) {
    .cols {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (max-width: 899px) {
    .foot .btn {
      flex: 1 1 auto;
    }
  }
</style>
