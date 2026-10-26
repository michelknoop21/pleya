<!--
  Serverbeheer, onderhoud (northstar 35): de back-ups van de server, de
  instellingen waaronder ze gemaakt worden, en terugzetten.

  Schrijfacties, en wat elk vraagt:
  - Nu een back-up maken: `POST /backups`. Geen bevestiging: het maakt alleen
    een bestand erbij. Er loopt er één tegelijk (409 `server.backup_busy`).
  - Hersteltest: `POST /backups/{id}/verify`. Draait in een eigen tijdelijke
    database; de echte blijft onaangeraakt, dus ook zonder bevestiging.
  - Terugzetten: `POST /backups/{id}/restore`, achter ConfirmDialog met de zin
    van de server letterlijk over te typen. Na de 202 is de server in
    onderhoud en herstart hij; de pagina laat de lijst los en wacht tot de
    server weer antwoordt (`waitForServer`), want een lijst van vóór de restore
    is een verouderd beeld. Een restore wordt nooit automatisch herhaald. Valt
    de verbinding weg vóór het antwoord, dan weet de pagina niet of hij begon,
    en zegt dat, in plaats van het nog eens te sturen.

  Zolang er een back-up of hersteltest loopt leest de pagina elke vier
  seconden opnieuw en zijn alle schrijfknoppen uit; daarna houdt het verversen
  op, zodat een rustige server geen verkeer maakt.
-->
<script lang="ts">
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Alert from '../../components/Alert.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { adminBackupsApi } from '../../api/adminBackups';
  import { TransportError } from '../../api/errors';
  import type { Backup, BackupList } from '../../api/types';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import AdminColumns from '../settings/AdminColumns.svelte';
  import { backupProblem, type BackupAction } from './backupErrors';
  import BackupsSettingsPanel from './BackupsSettingsPanel.svelte';
  import BackupsTable from './BackupsTable.svelte';
  import BackupsWarnings from './BackupsWarnings.svelte';
  import RestoreDialog from './RestoreDialog.svelte';
  import RestorePanel from './RestorePanel.svelte';
  import RestoringState from './RestoringState.svelte';
  import { BACKUP_POLL_MS, isLive, loadBackups, waitForServer, warnings } from './backups';

  const api = $derived(adminBackupsApi(session.client));

  let data = $state<BackupList | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let tick = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  let creating = $state(false);
  let verifying = $state(false);

  let restoreTarget = $state<Backup | null>(null);
  let restoreOpen = $state(false);
  let restoring = $state(false);
  let phase = $state<'waiting' | 'back' | 'signin' | 'timeout' | null>(null);
  let waitRun = $state(0);

  // De server meldt het onderdeel in `capabilities`; zonder weten we het niet en proberen we het.
  const unsupported = $derived(
    session.capabilities !== null && session.capabilities !== undefined && session.capabilities.backups !== true
  );

  $effect(() => {
    void attempt;
    void tick;
    if (phase !== null || unsupported) return;
    const controller = new AbortController();
    loadBackups(adminBackupsApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        if (data) {
          // De staande lijst blijft staan; het verversen stopt tot de bezoeker kiest.
          problem = backupProblem(err, 'list');
          retry = refresh;
        } else {
          failure = backupProblem(err, 'list').message;
        }
      });
    return () => controller.abort();
  });

  // Elke nieuwe stand zet de timer opnieuw, dus er loopt nooit meer dan één.
  $effect(() => {
    if (!data || phase !== null || !isLive(data)) return;
    const timer = setTimeout(() => (tick += 1), BACKUP_POLL_MS);
    return () => clearTimeout(timer);
  });

  // Na een restore: wachten tot de server antwoordt. Een nieuwe `waitRun` start opnieuw.
  $effect(() => {
    void waitRun;
    if (phase !== 'waiting') return;
    const controller = new AbortController();
    waitForServer(adminBackupsApi(session.client), { signal: controller.signal })
      .then((outcome) => {
        if (!controller.signal.aborted) phase = outcome === 'back' ? 'back' : outcome;
      })
      .catch(() => {
        if (!controller.signal.aborted) phase = 'timeout';
      });
    return () => controller.abort();
  });

  const now = $derived.by(() => {
    void data;
    return Date.now();
  });
  const live = $derived(data ? isLive(data) : false);
  const busy = $derived(live || creating || verifying || restoring);
  const notes = $derived(data ? warnings(data, now) : []);

  function refresh(): void {
    problem = null;
    tick += 1;
  }

  function reload(): void {
    problem = null;
    attempt += 1;
  }

  function fail(err: unknown, action: BackupAction, again: () => void): void {
    notice = null;
    problem = backupProblem(err, action);
    retry = again;
  }

  async function create(): Promise<void> {
    problem = null;
    notice = null;
    creating = true;
    try {
      await api.create();
      notice = t('admin.bak.notice.created');
    } catch (err) {
      fail(err, 'create', () => void create());
    } finally {
      creating = false;
      // Ook na een weigering: een 409 betekent dat er al een loopt, en dat moet zichtbaar zijn.
      tick += 1;
    }
  }

  async function verify(backup: Backup): Promise<void> {
    problem = null;
    notice = null;
    verifying = true;
    try {
      await api.verify(backup.id);
      notice = t('admin.bak.notice.verifying');
    } catch (err) {
      fail(err, 'verify', () => void verify(backup));
    } finally {
      verifying = false;
      tick += 1;
    }
  }

  function askRestore(backup: Backup): void {
    problem = null;
    notice = null;
    restoreTarget = backup;
    restoreOpen = true;
  }

  async function restore(): Promise<void> {
    const target = restoreTarget;
    // De zin van de server, niet wat er getypt werd; de dialoog stond alleen open
    // en bevestigde alleen als beide gelijk waren.
    const sentence = target?.restore_confirmation;
    if (!target || !sentence || restoring) return;
    restoring = true;
    try {
      await api.restore(target.id, sentence);
      restoreOpen = false;
      data = null;
      phase = 'waiting';
    } catch (err) {
      restoreOpen = false;
      if (err instanceof TransportError) {
        // Geen antwoord: de restore kan wel begonnen zijn. Nooit nog eens sturen.
        notice = null;
        problem = { code: 'client.transport', message: t('admin.bak.err.restoreUnknown'), wayOut: 'reload' };
      } else {
        fail(err, 'restore', reload);
      }
      // Ververs: na een weigering klopt de lijst, en na een 409 is hij mogelijk veranderd.
      tick += 1;
    } finally {
      restoring = false;
    }
  }

  function backToList(): void {
    phase = null;
    problem = null;
    notice = null;
    attempt += 1;
  }
</script>

<AdminPageHead
  title={t('admin.bak.title')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.diagnostics'), href: '/admin/diagnostics' },
    { label: t('admin.bak.title') }
  ]}
>
  {#snippet actions()}
    {#if !unsupported && phase === null}
      <button
        type="button"
        class="btn btn--secondary btn--sm create"
        disabled={busy || !data}
        title={live ? t('admin.bak.action.busy') : undefined}
        onclick={() => void create()}
      >
        <AdminIcon name="plus" size={16} />{creating ? t('admin.bak.creating') : t('admin.bak.create')}
      </button>
    {/if}
  {/snippet}
</AdminPageHead>

{#if unsupported}
  <StateView
    kind="error"
    alert={false}
    title={t('admin.bak.unsupported.title')}
    message={t('admin.bak.unsupported.body')}
  />
{:else if phase !== null}
  <RestoringState
    {phase}
    onlist={backToList}
    oncheck={() => {
      phase = 'waiting';
      waitRun += 1;
    }}
  />
{:else}
  {#if notice}
    <div class="msg"><Alert tone="info">{notice}</Alert></div>
  {/if}
  {#if problem}
    <div class="msg">
      <LibraryProblemAlert {problem} onretry={() => retry()} onreload={reload} />
    </div>
  {/if}

  {#if data}
    <BackupsWarnings items={notes} />
    <div class="stack">
      <BackupsTable items={data!.items} {now} schedule={data!.schedule} {busy} onverify={(b) => void verify(b)} onrestore={askRestore} />
      <p class="explain">{t('admin.bak.explain')}</p>
      <AdminColumns>
        {#snippet left()}
          <BackupsSettingsPanel list={data!} />
        {/snippet}
        {#snippet right()}
          <RestorePanel />
        {/snippet}
      </AdminColumns>
    </div>
  {:else if failure}
    <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
  {:else}
    <SkeletonPage variant="compact" />
  {/if}
{/if}

<RestoreDialog backup={restoreTarget} bind:open={restoreOpen} busy={restoring} onconfirm={() => void restore()} />

<style>
  .msg {
    margin-bottom: 14px;
  }

  .stack {
    display: grid;
    gap: 16px;
  }

  .explain {
    margin: -4px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  /* Onder 900 over de volle breedte, zoals 35@393 de knop tekent. */
  @media (max-width: 899px) {
    .create {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
