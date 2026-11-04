<!--
  Verbinding (30, rechts): hoe de server draait. Het bindadres en de vertrouwde
  proxy's komen uit `GET /server` en zijn omgevingsvariabelen, dus alleen
  lezen. Verbinding testen (`POST /server/connectivity-check`) roept het eigen
  publieke adres aan en meet of het antwoordt en of een range heel aankomt.
  Het contract geeft geen tijdstip van de meting mee; de meting staat hier dus
  zonder klok, alleen als "net gemeten".
-->
<script lang="ts">
  import type { ConnectivityCheck, ServerDetail } from '../../api/types';
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import FactList from './FactList.svelte';
  import { ENV_LISTEN, ENV_TRUSTED_PROXIES } from './network';

  interface Props {
    server: ServerDetail;
    check: ConnectivityCheck | null;
    busy: boolean;
    /** Zonder ingesteld publiek adres is er niets aan te roepen. */
    publicUrlSet: boolean;
    ontest: () => void;
  }

  let { server, check, busy, publicUrlSet, ontest }: Props = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.net.conn.title')}{/snippet}
  {#snippet actions()}
    {#if server.behind_proxy !== undefined}
      <StatusPill
        variant="dot"
        tone={server.behind_proxy ? 'ok' : 'idle'}
        label={server.behind_proxy ? t('admin.net.conn.behindProxy') : t('admin.net.conn.direct')}
      />
    {/if}
  {/snippet}
  <FactList>
    <dt>{t('admin.net.conn.listen')}</dt>
    <dd>
      {#if server.listen}<span class="mono">{server.listen}</span>{:else}<span class="muted">{t('admin.set.unknown')}</span>{/if}
      <span class="sub mono">{ENV_LISTEN}</span>
    </dd>
    <dt>{t('admin.net.conn.proxies')}</dt>
    <dd>
      {#if server.trusted_proxies && server.trusted_proxies.length > 0}
        <span class="mono">{server.trusted_proxies.join(', ')}</span>
      {:else}
        <span class="muted">{t('admin.net.conn.noProxies')}</span>
      {/if}
      <span class="sub mono">{ENV_TRUSTED_PROXIES}</span>
    </dd>
    <dt>{t('admin.net.conn.public')}</dt>
    <dd>
      {#if check}
        <StatusPill
          variant="dot"
          tone={check.public_url_reachable ? 'ok' : 'err'}
          label={check.public_url_reachable ? t('admin.net.conn.reachable') : t('admin.net.conn.unreachable')}
        />
      {:else}
        <span class="muted">{t('admin.net.conn.untested')}</span>
      {/if}
    </dd>
    <dt>{t('admin.net.conn.ranges')}</dt>
    <dd>
      {#if check}
        <StatusPill
          variant="dot"
          tone={check.range_intact ? 'ok' : 'err'}
          label={check.range_intact ? t('admin.net.conn.rangeOk') : t('admin.net.conn.rangeBroken')}
        />
      {:else}
        <span class="muted">{t('admin.net.conn.untested')}</span>
      {/if}
    </dd>
  </FactList>
  {#if check && !publicUrlSet}
    <p class="note">{t('admin.net.conn.hintNoUrl')}</p>
  {:else if check && !check.public_url_reachable}
    <p class="note">{t('admin.net.conn.hintUnreachable')}</p>
  {:else if check && !check.range_intact}
    <p class="note">{t('admin.net.conn.hintRange')}</p>
  {/if}
  <button type="button" class="btn btn--secondary btn--sm test" disabled={busy} onclick={ontest}>
    <AdminIcon name="refresh" size={16} />{busy ? t('admin.net.conn.testing') : t('admin.net.conn.test')}
  </button>
</Panel>

<style>
  .note {
    margin: 12px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .test {
    margin-top: 14px;
  }
</style>
