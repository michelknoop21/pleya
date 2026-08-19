<script lang="ts">
  /*
   * Het serveroverzicht.
   *
   * Uitsluitend wat `GET /server` en `GET /info` dragen. Scans starten, jobs
   * bekijken, opslag beheren en bibliotheken toevoegen hebben geen endpoint in
   * dit protocol; dat zijn G6 en G7 en die hebben eerst een fase nodig. Er
   * staat daarom ook geen knop die niets doet: DEC-046 zegt dat wat hier
   * zichtbaar is via /pleya/v1 gaat, en wat er niet is wordt niet getekend.
   */
  import { session } from '$lib/stores/session.svelte';
  import { formatCount, formatDate } from '$lib/util/format';
  import { plural, t } from '$lib/i18n';

  const capabilityRows = $derived.by(() => {
    const caps = session.capabilities;
    if (!caps) return [] as { key: string; on: boolean }[];
    return Object.entries(caps).map(([key, value]) => ({ key, on: Boolean(value) }));
  });
</script>

<svelte:head><title>{t('server.title')} · {t('app.name')}</title></svelte:head>

<div class="page">
  <h1 class="t-headline">{t('server.title')}</h1>

  {#if session.server}
    <section class="card-surface panel">
      <dl class="rows">
        <div class="rows__row">
          <dt class="t-small">{t('server.name')}</dt>
          <dd class="t-body">{session.server.name}</dd>
        </div>
        <div class="rows__row">
          <dt class="t-small">{t('server.version')}</dt>
          <dd class="t-body">{session.server.version}</dd>
        </div>
        <div class="rows__row">
          <dt class="t-small">{t('server.startedAt')}</dt>
          <dd class="t-body">{formatDate(session.server.started_at) ?? session.server.started_at}</dd>
        </div>
        <div class="rows__row">
          <dt class="t-small">{t('server.id')}</dt>
          <dd class="t-body mono">{session.server.id}</dd>
        </div>
      </dl>
    </section>
  {/if}

  {#if session.info}
    <section class="card-surface panel">
      <h2 class="t-title">{t('server.protocol')}</h2>
      <dl class="rows">
        <div class="rows__row">
          <dt class="t-small">{t('server.featureLevel')}</dt>
          <dd class="t-body">{session.info.protocol.feature_level}</dd>
        </div>
        <div class="rows__row">
          <dt class="t-small">{t('server.profile')}</dt>
          <dd class="t-body">{session.info.protocol.profile}</dd>
        </div>
      </dl>
    </section>

    <section class="card-surface panel">
      <h2 class="t-title">{t('server.capabilities')}</h2>
      <ul class="caps">
        {#each capabilityRows as row (row.key)}
          <li class="caps__row">
            <span class="caps__dot" class:caps__dot--on={row.on} aria-hidden="true"></span>
            <span class="t-body">{row.key}</span>
            <span class="t-small">
              {row.on ? t('server.capabilityOn') : t('server.capabilityOff')}
            </span>
          </li>
        {/each}
      </ul>
    </section>
  {/if}

  <section class="card-surface panel">
    <h2 class="t-title">{t('server.libraries')}</h2>
    <ul class="rows">
      {#each session.libraries as library (library.id)}
        <li class="rows__row">
          <span class="t-body">{library.title}</span>
          <span class="t-small">
            {library.kind} · {plural('libraries.itemCount', library.item_count, {
              count: formatCount(library.item_count)
            })}
          </span>
        </li>
      {/each}
    </ul>
  </section>

  <button type="button" class="btn btn--quiet signout" onclick={() => session.signOut()}>
    {t('common.logout')}
  </button>
</div>

<style>
  .page {
    display: flex;
    flex-direction: column;
    gap: var(--space-1-5);
    padding: var(--space-1-5) var(--page-inset, var(--space));
    max-width: 780px;
  }

  .panel {
    display: flex;
    flex-direction: column;
    gap: var(--space);
    padding: var(--space-1-5);
    border: 1px solid var(--outline);
  }

  .rows {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    margin: 0;
  }

  .rows__row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-half) var(--space);
    align-items: baseline;
    justify-content: space-between;
  }

  .rows__row dt,
  .rows__row dd {
    margin: 0;
  }

  .mono {
    font-variant-numeric: tabular-nums;
    word-break: break-all;
  }

  .caps {
    display: grid;
    gap: var(--space-half);
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  }

  .caps__row {
    display: flex;
    align-items: center;
    gap: var(--space-half);
  }

  .caps__row .t-small {
    margin-inline-start: auto;
  }

  .caps__dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--outline);
    flex: 0 0 auto;
  }

  .caps__dot--on {
    background: var(--success);
  }

  .signout {
    align-self: flex-start;
  }
</style>
