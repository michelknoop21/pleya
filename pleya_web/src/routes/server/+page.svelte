<script lang="ts">
  /*
   * Mijn Pleya, het serveroverzicht.
   *
   * Uitsluitend wat `GET /server` en `GET /info` dragen. Scans starten, jobs
   * bekijken, opslag beheren en bibliotheken toevoegen hebben geen endpoint in
   * dit protocol; dat zijn G6 en G7 en die hebben eerst een fase nodig. Er
   * staat daarom ook geen knop die niets doet: DEC-046 zegt dat wat hier
   * zichtbaar is via /pleya/v1 gaat, en wat er niet is wordt niet getekend.
   * De indeling van beeld 11 (account, content, toestellen) is S8.6.
   */
  import DataTable, { type Column } from '$lib/components/DataTable.svelte';
  import LanguagePicker from '$lib/components/LanguagePicker.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import Panel from '$lib/components/Panel.svelte';
  import StatusPill from '$lib/components/StatusPill.svelte';
  import ThemePicker from '$lib/components/ThemePicker.svelte';
  import type { Library } from '$lib/api/types';
  import { session } from '$lib/stores/session.svelte';
  import { formatCount, formatDate } from '$lib/util/format';
  import { plural, t } from '$lib/i18n';

  const capabilityRows = $derived.by(() => {
    const caps = session.capabilities;
    if (!caps) return [] as { key: string; on: boolean }[];
    return Object.entries(caps).map(([key, value]) => ({ key, on: Boolean(value) }));
  });

  const libraryColumns: Column[] = [
    { key: 'title', label: t('server.name') },
    { key: 'kind', label: t('server.libraryKind') },
    { key: 'item_count', label: t('server.libraryItems'), align: 'end' }
  ];

  // Dezelfde namen als de navigatie; de ruwe waarde blijft in data-library-kind.
  function kindLabel(library: Library): string {
    return library.kind === 'movies' ? t('nav.films') : t('nav.series');
  }
</script>

<svelte:head><title>{t('server.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <PageHeader title={t('server.title')} />

  <div class="stack">
    <!-- Mijn Pleya is de plek voor thema en taal: de topbalk heeft er geen ruimte voor. -->
    <Panel level={2}>
      {#snippet title()}<span id="server-theme">{t('settings.theme')}</span>{/snippet}
      <ThemePicker labelledby="server-theme" />
    </Panel>

    <Panel level={2}>
      {#snippet title()}<span id="server-language">{t('settings.language')}</span>{/snippet}
      <LanguagePicker labelledby="server-language" />
    </Panel>

    {#if session.server}
      <Panel level={2}>
        {#snippet title()}{t('server.about')}{/snippet}
        <dl class="kv">
          <div class="kv__row">
            <dt>{t('server.name')}</dt>
            <dd>{session.server.name}</dd>
          </div>
          <div class="kv__row">
            <dt>{t('server.version')}</dt>
            <dd>{session.server.version}</dd>
          </div>
          <div class="kv__row">
            <dt>{t('server.startedAt')}</dt>
            <dd>{formatDate(session.server.started_at) ?? session.server.started_at}</dd>
          </div>
          <div class="kv__row">
            <dt>{t('server.id')}</dt>
            <dd class="kv__mono">{session.server.id}</dd>
          </div>
        </dl>
      </Panel>
    {/if}

    {#if session.info}
      <Panel level={2}>
        {#snippet title()}{t('server.protocol')}{/snippet}
        <dl class="kv">
          <div class="kv__row">
            <dt>{t('server.featureLevel')}</dt>
            <dd>{session.info.protocol.feature_level}</dd>
          </div>
          <div class="kv__row">
            <dt>{t('server.profile')}</dt>
            <dd>{session.info.protocol.profile}</dd>
          </div>
        </dl>
      </Panel>

      <Panel level={2}>
        {#snippet title()}{t('server.capabilities')}{/snippet}
        <ul class="caps">
          {#each capabilityRows as row (row.key)}
            <li class="caps__row">
              <span class="caps__key">{row.key}</span>
              <StatusPill
                variant="dot"
                tone={row.on ? 'ok' : 'idle'}
                label={row.on ? t('server.capabilityOn') : t('server.capabilityOff')}
              />
            </li>
          {/each}
        </ul>
      </Panel>
    {/if}

    <DataTable
      columns={libraryColumns}
      rows={session.libraries}
      label={t('server.libraries')}
      rowKey={(library) => library.id}
      rowData={(library) => ({
        'data-library-kind': library.kind,
        'data-library-id': library.id
      })}
      stack
    >
      {#snippet title()}{t('server.libraries')}{/snippet}
      {#snippet cell(library, column)}
        {#if column.key === 'kind'}
          {kindLabel(library)}
        {:else if column.key === 'item_count'}
          {plural('libraries.itemCount', library.item_count, {
            count: formatCount(library.item_count)
          })}
        {:else}
          {library.title}
        {/if}
      {/snippet}
    </DataTable>

    <button type="button" class="btn btn--quiet signout" onclick={() => void session.signOut()}>
      {t('common.logout')}
    </button>
  </div>
</div>

<style>
  /* web.css .page: de inzet van de pagina, 8 boven de kop. */
  .page {
    padding: var(--page-top) var(--inset) var(--space-2);
    max-width: 780px;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
  }

  /* Sleutel-waarderijen (.kv): sleutel in gedimde inkt, waarde rechts. */
  .kv {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    margin: 0;
  }

  .kv__row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-half) var(--space);
    align-items: baseline;
    justify-content: space-between;
    min-width: 0;
  }

  .kv__row dt {
    font-size: 13px;
    color: var(--ink-3);
  }

  .kv__row dd {
    min-width: 0;
    margin: 0;
    font-size: 14px;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .kv__mono {
    font-family: var(--font-mono);
    font-size: var(--text-mono-size);
    font-variant-numeric: tabular-nums;
  }

  .caps {
    display: grid;
    gap: var(--space-half) var(--space);
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    margin: 0;
  }

  /*
   * "niet beschikbaar" is twee keer zo lang als "available", en een sleutel als
   * watch_state_ownership heeft geen enkel breekpunt. Met wrap zakt de status
   * naar een eigen regel in plaats van over de sleutel te schuiven.
   */
  .caps__row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 2px var(--space-half);
    min-width: 0;
  }

  .caps__key {
    min-width: 0;
    font-size: 14px;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .signout {
    align-self: flex-start;
  }
</style>
