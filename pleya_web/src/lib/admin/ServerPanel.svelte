<!--
  Het serverpaneel van scherm 20 (`.kv` in web.css): naam, adres, versie,
  database en gebruikers. Alles komt uit `GET /server` (de beheervelden), uit
  `GET /info` en uit `GET /users`. Het aantal ingelogde toestellen uit de
  northstar ontbreekt: dat vraagt `GET /sessions?user_id=` per gebruiker.
-->
<script lang="ts">
  import Panel from '../components/Panel.svelte';
  import type { Info } from '../api/types';
  import { t } from '../i18n';
  import { formatCount } from '../util/format';
  import type { OverviewData } from './overview';

  let { data, info }: { data: OverviewData; info: Info | null } = $props();

  const address = $derived(data.server.public_url || data.server.web_origin || null);
</script>

<Panel>
  {#snippet title()}{t('admin.server.title')}{/snippet}
  <dl class="kv">
    <dt>{t('admin.server.name')}</dt>
    <dd>{data.server.name}</dd>
    <dt>{t('admin.server.address')}</dt>
    {#if address}
      <dd class="mono">{address}</dd>
    {:else}
      <dd class="muted">{t('admin.server.addressUnset')}</dd>
    {/if}
    <dt>{t('admin.server.version')}</dt>
    <dd>
      {#if info}
        {t('admin.server.versionValue', {
          version: data.server.version,
          major: info.protocol.major,
          level: info.protocol.feature_level
        })}
      {:else}
        {data.server.version}
      {/if}
    </dd>
    {#if data.server.database}
      <dt>{t('admin.server.database')}</dt>
      <dd>
        {t('admin.server.databaseValue', {
          version: data.server.database.version,
          schema: data.server.database.schema
        })}
      </dd>
    {/if}
    <dt>{t('admin.server.users')}</dt>
    <dd>{formatCount(data.users.length)}</dd>
  </dl>
</Panel>

<style>
  .kv {
    display: grid;
    grid-template-columns: 110px minmax(0, 1fr);
    gap: 8px 16px;
    margin: 0;
    font-size: 14px;
  }

  dt {
    color: var(--ink-3);
  }

  dd {
    margin: 0;
    min-width: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .muted {
    color: var(--ink-3);
  }
</style>
