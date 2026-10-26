<!--
  Oude toestellen opruimen (DEC-164), voor scherm 27 en 31: alle sessies die
  langer dan 30, 60 of 90 dagen niet gezien zijn, behalve het toestel waarmee
  je nu kijkt en API-tokens. Eerst een bevestiging die het aantal en de
  toestellen noemt, dan één `DELETE /sessions/{id}` per toestel met de stand
  erbij. Een fout stopt de rij niet; achteraf staat er hoeveel er lukte en
  hoeveel niet, en de lijst wordt ververst.

  Er is geen route die dit in één keer doet, en de server ruimt zelf al op wat
  niet meer kan verversen. Dit is de knop voor wat nog wel kan, maar door
  niemand meer gebruikt wordt.
-->
<script lang="ts" module>
  import type { UserSession } from '../api/adminUsers';

  export interface CleanupItem {
    session: UserSession;
    /** De gebruikersnaam, op een scherm met toestellen van meer gebruikers. */
    user?: string;
  }
</script>

<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Select from '../components/Select.svelte';
  import { plural, t } from '../i18n';
  import { formatRelative } from '../util/format';
  import {
    CLEANUP_PERIODS,
    DEFAULT_CLEANUP_PERIOD,
    deviceLabel,
    revokeEach,
    staleSessions
  } from './sessionCleanup';

  interface Props {
    items: CleanupItem[];
    revoke: (sessionId: string) => Promise<unknown>;
    /** Na afloop: de lijst opnieuw lezen. */
    ondone: () => Promise<void> | void;
  }

  let { items, revoke, ondone }: Props = $props();

  /** Zoveel toestellen noemt de dialoog bij naam; de rest is "en nog N". */
  const SHOWN = 6;

  let open = $state(false);
  let days = $state(String(DEFAULT_CLEANUP_PERIOD));
  let now = $state(Date.now());
  let busy = $state(false);
  let settled = $state(0);
  let result = $state<{ done: number; failed: number; total: number } | null>(null);

  const sessionOf = (item: CleanupItem) => item.session;
  const candidates = $derived(staleSessions(items, sessionOf, Number(days), now));
  const offered = $derived(staleSessions(items, sessionOf, Math.min(...CLEANUP_PERIODS), Date.now()).length > 0);
  const periods = CLEANUP_PERIODS.map((n) => ({ value: String(n), label: t('admin.devices.cleanup.days', { count: n }) }));

  function ask(): void {
    now = Date.now();
    days = String(DEFAULT_CLEANUP_PERIOD);
    open = true;
  }

  async function run(): Promise<void> {
    const todo = candidates;
    if (todo.length === 0 || busy) return;
    busy = true;
    settled = 0;
    result = null;
    const outcome = await revokeEach(
      todo,
      (item) => revoke(item.session.id),
      (n) => (settled = n)
    );
    result = { done: outcome.done.length, failed: outcome.failed.length, total: todo.length };
    busy = false;
    open = false;
    await ondone();
  }

  function itemText(item: CleanupItem): string {
    const device = deviceLabel(item.session, true);
    const seen = formatRelative(item.session.last_seen_at) ?? '';
    return item.user
      ? t('admin.devices.cleanup.itemOf', { device, user: item.user, seen })
      : t('admin.devices.cleanup.item', { device, seen });
  }
</script>

{#if offered || result}
  <div class="cleanup">
    {#if offered}
      <button type="button" class="btn btn--ghost btn--sm" onclick={ask}>
        {t('admin.devices.cleanup.open')}
      </button>
    {/if}
    {#if result && result.failed === 0}
      <Alert tone="info">{plural('admin.devices.cleanup.done', result.done)}</Alert>
    {:else if result}
      <Alert tone="warn">
        {t('admin.devices.cleanup.partial', { done: result.done, total: result.total, failed: result.failed })}
        {#snippet actions()}
          <button type="button" class="btn btn--secondary btn--sm" onclick={ask}>
            {t('admin.devices.cleanup.retry')}
          </button>
        {/snippet}
      </Alert>
    {/if}
  </div>
{/if}

<ConfirmDialog
  bind:open
  {busy}
  disabled={candidates.length === 0}
  title={t('admin.devices.cleanup.title')}
  message={t('admin.devices.cleanup.body')}
  confirmLabel={plural('admin.devices.cleanup.confirm', candidates.length)}
  onconfirm={() => void run()}
>
  <div class="body">
    <Select label={t('admin.devices.cleanup.period')} options={periods} bind:value={days} disabled={busy} />
    {#if candidates.length === 0}
      <p class="none">{t('admin.devices.cleanup.none')}</p>
    {:else}
      <p class="count">{plural('admin.devices.cleanup.count', candidates.length)}</p>
      <ul class="list">
        {#each candidates.slice(0, SHOWN) as item (item.session.id)}
          <li>{itemText(item)}</li>
        {/each}
      </ul>
      {#if candidates.length > SHOWN}
        <p class="more">{t('admin.devices.cleanup.more', { count: candidates.length - SHOWN })}</p>
      {/if}
    {/if}
    <!-- Op één regel, zodat hij zonder stand echt leeg is en :empty hem verbergt. -->
    <p class="progress" role="status">{busy ? t('admin.devices.cleanup.progress', { done: settled, total: candidates.length }) : ''}</p>
  </div>
</ConfirmDialog>

<style>
  .cleanup {
    display: grid;
    justify-items: start;
    gap: 10px;
    margin-top: 10px;
  }

  .cleanup :global(.alert) {
    justify-self: stretch;
  }

  .body {
    display: grid;
    gap: 10px;
    margin-top: 6px;
  }

  .count,
  .none,
  .more,
  .progress {
    margin: 0;
  }

  .progress:empty {
    display: none;
  }

  .progress {
    font-weight: 600;
    color: var(--ink);
  }

  .list {
    display: grid;
    gap: 4px;
    margin: 0;
    padding-left: 20px;
    list-style: disc;
    overflow-wrap: anywhere;
  }
</style>
