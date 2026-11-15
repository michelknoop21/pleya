<!--
  De filterregel boven het raster. Kijkstatus staat er als directe pillen; elke
  andere groep (genre, jaar, kwaliteit, audio, kijkwijzer) is een pil die zijn
  keuzes eronder openklapt. Een keuze geldt meteen, zonder aparte toepasknop:
  de lijst eronder is het antwoord. Wat actief is staat als ingedrukte pil in
  de regel en gaat met één druk weer weg.

  Een groep zonder waarden in de facetten verschijnt niet. Zolang de facetten
  laden zijn de groepen uit, maar actieve filters blijven te verwijderen.
-->
<script lang="ts">
  import Chips, { type ChipOption } from './Chips.svelte';
  import type { Facets, FacetValue } from '../api/types';
  import { catalogFilterCount, type CatalogFilters } from '../util/catalogFilters';
  import { formatLanguage } from '../util/format';
  import { t } from '../i18n';

  interface Props {
    filters: CatalogFilters;
    facets: Facets | null;
    loading?: boolean;
    watchState?: boolean;
    onapply: (filters: CatalogFilters) => void;
  }
  let { filters, facets, loading = false, watchState = false, onapply }: Props = $props();

  type Group = Exclude<keyof CatalogFilters, 'watch'>;
  type Watch = NonNullable<CatalogFilters['watch']>;
  const uid = $props.id();
  const quality: Record<string, string> = { sd: 'SD', hd: 'HD', fhd: 'Full HD', uhd: '4K' };
  const plain = (value: string) => value;

  let openKey = $state<Group | null>(null);
  const openers: Partial<Record<Group, HTMLButtonElement>> = {};

  const watchOptions = $derived<{ id: Watch | undefined; label: string }[]>([
    { id: undefined, label: t('catalog.all') },
    { id: 'unwatched', label: t('catalog.unwatched') },
    { id: 'in_progress', label: t('catalog.inProgress') },
    { id: 'watched', label: t('catalog.watched') }
  ]);

  function options(values: FacetValue[], selected: string[], text: (value: string) => string): ChipOption[] {
    const entries = new Map<string, ChipOption>(values.filter(row => row.value).map(row => [row.value, { id: row.value, label: text(row.value), count: row.count }]));
    for (const value of selected) if (!entries.has(value)) entries.set(value, { id: value, label: text(value), count: undefined });
    return [...entries.values()];
  }

  const groups = $derived(([
    { key: 'genre', label: t('catalog.genre'), values: facets?.genres, text: plain },
    { key: 'year', label: t('catalog.year'), values: facets?.years, text: plain },
    { key: 'resolution', label: t('catalog.quality'), values: facets?.resolutions, text: (value: string) => quality[value] ?? value },
    { key: 'audio_language', label: t('item.audio'), values: facets?.audio_languages, text: (value: string) => formatLanguage(value) ?? value },
    { key: 'content_rating', label: t('catalog.contentRating'), values: facets?.content_ratings, text: plain }
  ] satisfies { key: Group; label: string; values: FacetValue[] | undefined; text: (value: string) => string }[]).map(group => {
    const selected: string[] = filters[group.key] ?? [];
    return {
      ...group,
      selected,
      // Een kwaliteit die deze client niet kent is te zien maar niet te kiezen.
      options: options(group.values ?? [], selected, group.text)
        .map(option => group.key === 'resolution' ? { ...option, disabled: !Object.hasOwn(quality, option.id) } : option)
    };
  }).filter(group => group.options.length > 0));
  const current = $derived(groups.find(group => group.key === openKey));
  const active = $derived(groups.flatMap(group => group.selected.map(value => ({ key: group.key, value, label: `${group.label}: ${group.text(value)}` }))));

  function setGroup(key: Group, values: string[]): void {
    const next: CatalogFilters = { ...filters };
    delete next[key];
    onapply(values.length ? { ...next, [key]: values } : next);
  }
  function setWatch(watch: Watch | undefined): void {
    const next: CatalogFilters = { ...filters };
    delete next.watch;
    onapply(watch ? { ...next, watch } : next);
  }
  function close(): void {
    const key = openKey;
    openKey = null;
    if (key) openers[key]?.focus();
  }
</script>

<svelte:window onkeydown={event => { if (openKey && event.key === 'Escape') close(); }} />

<div class="filter-bar" aria-busy={loading}>
  {#if watchState}
    <div class="filter-set" role="group" aria-label={t('catalog.watch')}>
      {#each watchOptions as option (option.id ?? '')}
        <button type="button" class="pill" aria-pressed={filters.watch === option.id} onclick={() => setWatch(option.id)}>{option.label}</button>
      {/each}
    </div>
    <span class="filter-rule" aria-hidden="true"></span>
  {/if}
  {#each groups as group (group.key)}
    <button
      type="button"
      class="pill"
      bind:this={openers[group.key]}
      disabled={facets === null}
      aria-expanded={openKey === group.key}
      aria-controls="{uid}-panel"
      onclick={() => (openKey = openKey === group.key ? null : group.key)}
    >{group.label}</button>
  {/each}
  {#if active.length}
    <div class="filter-set" role="group" aria-label={t('catalog.activeFilters')}>
      {#each active as filter (`${filter.key}:${filter.value}`)}
        <button
          type="button"
          class="pill"
          aria-pressed="true"
          onclick={() => setGroup(filter.key, (filters[filter.key] ?? []).filter(value => value !== filter.value))}
        >{filter.label} <span aria-hidden="true">×</span></button>
      {/each}
    </div>
  {/if}
  {#if catalogFilterCount(filters) > 0}
    <button type="button" class="filter-clear" onclick={() => onapply({})}>{t('catalog.clear')}</button>
  {/if}
</div>
<div id="{uid}-panel">
  {#if current && facets !== null}
    <div class="filter-panel">
      <Chips label={current.label} options={current.options} selected={current.selected} multiple onchange={values => setGroup(current.key, values)} />
      <p class="note">{t('catalog.countsNote')}</p>
    </div>
  {/if}
</div>

<style>
  .filter-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 16px; min-width: 0; }
  .filter-set { display: contents; }
  .filter-rule { width: 1px; height: 24px; margin: 0 6px; background: var(--hairline-strong); }
  .pill {
    min-height: var(--button-height);
    padding: 0 16px;
    border: 1px solid color-mix(in srgb, var(--text) 22%, transparent);
    border-radius: var(--radius-pill);
    background: transparent;
    color: var(--ink);
    font-size: 14px;
    font-weight: 500;
    white-space: nowrap;
    cursor: pointer;
  }
  .pill[aria-pressed='true'] { background: var(--ink); border-color: var(--ink); color: var(--bg); }
  .pill[aria-expanded='true'] { border-color: var(--ink); }
  .pill:disabled { opacity: 0.5; cursor: default; }
  .filter-clear {
    min-height: var(--button-height);
    margin-left: 6px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink);
    font-size: 14px;
    text-decoration: underline;
    cursor: pointer;
  }
  .filter-panel { margin-bottom: 16px; padding: 12px 16px; border-radius: var(--radius-md); background: var(--panel); }
  /* In het paneel lopen de keuzes over meer regels in plaats van te scrollen. */
  .filter-panel :global(.chips) { flex-wrap: wrap; overflow: visible; }
  .note { color: var(--ink-2); font-size: 13px; margin: 8px 0 0; }
  @media (hover: hover) {
    .pill:not(:disabled):not([aria-pressed='true']):hover { border-color: color-mix(in srgb, var(--text) 45%, transparent); }
  }
  @media (max-width: 899px) {
    .pill { padding: 0 12px; }
    .filter-rule { display: none; }
  }
</style>
