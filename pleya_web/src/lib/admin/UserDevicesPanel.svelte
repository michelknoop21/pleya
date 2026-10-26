<!--
  Het paneel Toestellen van scherm 27: de sessies van deze gebruiker
  (`GET /sessions?user_id=`), per sessie Uitloggen (`DELETE /sessions/{id}`) en
  Overal uitloggen. Het contract kent geen route om alles in één keer in te
  trekken; Overal uitloggen trekt de sessies dus één voor één in. Een
  ingetrokken sessie komt niet meer in de lijst, dus de northstar-pil
  "ingetrokken" bestaat hier niet. De sessie waarmee je zelf kijkt heeft geen
  knop: die intrekken zou jezelf uitloggen.
-->
<script lang="ts">
  import type { UserSession } from '../api/adminUsers';
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { t } from '../i18n';
  import { formatDate, formatRelative } from '../util/format';

  interface Props {
    /** Null als de sessies niet te lezen waren. */
    sessions: UserSession[] | null;
    /** Id's van sessies waarvoor nu een intrekking loopt. */
    revoking: Record<string, boolean>;
    onrevoke: (session: UserSession) => void;
    onrevokeAll: () => void;
  }

  let { sessions, revoking, onrevoke, onrevokeAll }: Props = $props();

  const revocable = $derived((sessions ?? []).filter((s) => !s.current));
</script>

<Panel>
  {#snippet title()}{t('admin.users.devices.title')}{/snippet}
  {#if sessions === null}
    <p class="empty">{t('admin.users.devices.unreadable')}</p>
  {:else if sessions.length === 0}
    <p class="empty">{t('admin.users.devices.empty')}</p>
  {:else}
    <ul class="list">
      {#each sessions as item (item.id)}
        <li class="row" data-session={item.id}>
          <span class="ico"><AdminIcon name={item.kind === 'api' ? 'cpu' : 'globe'} size={18} /></span>
          <span class="text">
            <span class="name">{item.device_name}</span>
            <span class="meta">
              {t('admin.users.devices.meta', {
                created: formatDate(item.created_at) ?? '',
                seen: formatRelative(item.last_seen_at) ?? ''
              })}
            </span>
          </span>
          {#if item.kind === 'api'}
            <StatusPill size="sm" label={t('admin.users.devices.token')} />
          {/if}
          {#if item.current}
            <StatusPill size="sm" tone="ok" label={t('admin.users.devices.thisOne')} />
          {:else}
            <button
              type="button"
              class="btn btn--secondary btn--sm"
              disabled={revoking[item.id]}
              aria-label={t('admin.users.devices.signOutNamed', { device: item.device_name })}
              onclick={() => onrevoke(item)}
            >
              {t('admin.users.devices.signOut')}
            </button>
          {/if}
        </li>
      {/each}
    </ul>
    {#if revocable.length > 0}
      <button type="button" class="btn btn--ghost btn--sm all" onclick={onrevokeAll}>
        {t('admin.users.devices.signOutAll')}
      </button>
    {/if}
  {/if}
</Panel>

<style>
  .empty {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  .list {
    display: grid;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 0;
    border-bottom: 1px solid var(--hairline);
  }

  .row:last-child {
    border-bottom: 0;
  }

  .ico {
    flex: none;
    color: var(--ink-3);
  }

  .text {
    display: grid;
    flex: 1 1 auto;
    min-width: 0;
  }

  .name {
    font-size: 14px;
    font-weight: 600;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .meta {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .all {
    margin-top: 10px;
  }
</style>
