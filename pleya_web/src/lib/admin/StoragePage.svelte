<!--
  Serverbeheer, opslag (northstar 24): de roots van de server met hun
  bestandssysteem, inodevertrouwen en vrije ruimte, en een waarschuwing zodra
  een root niet gemount is. Opnieuw controleren (`POST /storage/roots/recheck`)
  plant een meetronde in; die loopt via de jobwachtrij, dus de pagina leest de
  roots een paar seconden later nog één keer.

  Alleen lezen en die ene actie: er is geen route om een root toe te voegen of
  te verwijderen. De roots komen uit PLEYA_SERVER_MEDIA_DIRS.
-->
<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import { describeError } from '../api/errors';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import LibraryProblemAlert from './LibraryProblemAlert.svelte';
  import { opsProblem } from './opsErrors';
  import StorageTable from './StorageTable.svelte';
  import {
    RECHECK_REFRESH_MS,
    libraryNames,
    loadStorage,
    storageHeadline,
    unmountedRoots,
    type StorageData
  } from './storage';
  import type { LibraryProblem } from './libraryErrors';

  const api = $derived(adminApi(session.client));

  let data = $state<StorageData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  let busy = $state(false);
  let refreshTick = $state(0);

  $effect(() => {
    void attempt;
    void refreshTick;
    const controller = new AbortController();
    loadStorage(adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        // Een mislukte verversing laat de staande tabel staan.
        if (data) {
          problem = opsProblem(err, t('admin.nav.storage'));
          retry = reload;
        } else failure = describeError(err);
      });
    return () => controller.abort();
  });

  // Eén keer herlezen nadat de meting is ingepland, en niet blijven pollen.
  let refreshTimer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => () => clearTimeout(refreshTimer));

  async function recheck(): Promise<void> {
    problem = null;
    notice = null;
    busy = true;
    try {
      await api.recheckStorageRoots();
      notice = t('admin.sto.notice.rechecked');
      clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => (refreshTick += 1), RECHECK_REFRESH_MS);
    } catch (err) {
      problem = opsProblem(err, t('admin.nav.storage'));
      retry = () => void recheck();
    } finally {
      busy = false;
    }
  }

  function reload(): void {
    problem = null;
    attempt += 1;
  }

  const down = $derived(data ? unmountedRoots(data.roots) : []);
</script>

<AdminPageHead
  title={t('admin.nav.storage')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.storage') }]}
>
  {#snippet actions()}
    {#if data}<p class="headline">{storageHeadline(data.roots)}</p>{/if}
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
  {#if down.length > 0}
    {@const names = libraryNames(down)}
    <div class="msg">
      <Alert
        tone="err"
        title={down.length === 1
          ? t('admin.sto.alert.single', { path: down[0]!.path })
          : t('admin.sto.alert.multi', { count: down.length })}
      >
        {t('admin.sto.alert.body')}
        {#if names.length > 0}{t('admin.sto.alert.libraries', { names: names.join(', ') })}{/if}
        {#snippet actions()}
          <button
            type="button"
            class="btn btn--secondary btn--sm"
            disabled={busy}
            onclick={() => void recheck()}
          >
            <AdminIcon name="refresh" size={16} />{t('admin.sto.action.recheck')}
          </button>
        {/snippet}
      </Alert>
    </div>
  {/if}

  <StorageTable roots={data.roots} scanning={data.scanning} />

  <div class="info">
    <Panel>
      {#snippet title()}{t('admin.sto.manage.title')}{/snippet}
      <p class="body">
        {t('admin.sto.manage.before')}<span class="mono">PLEYA_SERVER_MEDIA_DIRS</span>{t(
          'admin.sto.manage.after'
        )}
      </p>
    </Panel>
    <Panel>
      {#snippet title()}{t('admin.sto.inodeInfo.title')}{/snippet}
      {#snippet actions()}
        {#if down.length === 0}
          <button
            type="button"
            class="btn btn--ghost btn--sm"
            disabled={busy}
            onclick={() => void recheck()}
          >
            <AdminIcon name="refresh" size={16} />{t('admin.sto.action.recheck')}
          </button>
        {/if}
      {/snippet}
      <p class="body">
        {t('admin.sto.inodeInfo.before')}<span class="mono">PLEYA_SERVER_INODE_TRUST</span>{t(
          'admin.sto.inodeInfo.after'
        )}
      </p>
    </Panel>
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

  .headline {
    margin: 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--ink-2);
  }

  .info {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
    margin-top: 16px;
  }

  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .body .mono {
    font-size: 12px;
    color: var(--ink-2);
  }

  @media (max-width: 899px) {
    .info {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
