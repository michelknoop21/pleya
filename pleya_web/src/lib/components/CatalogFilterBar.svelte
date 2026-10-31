<script lang="ts">
  import Chips, { type ChipOption } from './Chips.svelte';
  import ConfirmDialog from './ConfirmDialog.svelte';
  import type { Facets, FacetValue } from '../api/types';
  import { catalogFilterCount, type CatalogFilters } from '../util/catalogFilters';
  import { t } from '../i18n';

  interface Props {
    filters: CatalogFilters;
    facets: Facets | null;
    loading?: boolean;
    watchState?: boolean;
    onapply: (filters: CatalogFilters) => void;
  }
  let { filters, facets, loading = false, watchState = false, onapply }: Props = $props();
  let open = $state(false);
  let draft = $state<CatalogFilters>({});
  const count = $derived(catalogFilterCount(filters));
  type Key = keyof CatalogFilters;
  type Resolution = NonNullable<CatalogFilters['resolution']>[number];
  const quality: Record<Resolution, string> = { sd: 'SD', hd: 'HD', fhd: 'Full HD', uhd: '4K' };
  const watchLabels = $derived({ unwatched: t('catalog.unwatched'), in_progress: t('catalog.inProgress'), watched: t('catalog.watched') });

  function options(values: FacetValue[], selected: string[], label = (value: string) => value): ChipOption[] {
    const entries = new Map<string, ChipOption>(values.filter(row => row.value).map(row => [row.value, { id: row.value, label: label(row.value), count: row.count }]));
    for (const value of selected) if (!entries.has(value)) entries.set(value, { id: value, label: label(value), count: undefined });
    return [...entries.values()];
  }

  const groups = $derived([
    { key: 'genre' as const, label: t('catalog.genre'), options: options(facets?.genres ?? [], draft.genre ?? []) },
    { key: 'year' as const, label: t('catalog.year'), options: options(facets?.years ?? [], draft.year ?? []) },
    { key: 'resolution' as const, label: t('catalog.quality'), options: options(facets?.resolutions ?? [], draft.resolution ?? [], value => quality[value as Resolution] ?? value).map(option => ({ ...option, disabled: !Object.hasOwn(quality, option.id) })) },
    ...(watchState && facets ? [{ key: 'watch' as const, label: t('catalog.watch'), options: [
      { id: '', label: t('catalog.all'), count: facets.watch.unwatched + facets.watch.watched },
      ...Object.entries(watchLabels).map(([id, label]) => ({ id, label, count: facets.watch[id as keyof typeof watchLabels] }))
    ] }] : [])
  ]);
  const active = $derived([
    ...(filters.genre ?? []).map(value => ({ key: 'genre' as const, value, label: value })),
    ...(filters.year ?? []).map(value => ({ key: 'year' as const, value, label: value })),
    ...(filters.resolution ?? []).map(value => ({ key: 'resolution' as const, value, label: quality[value] })),
    ...(filters.watch ? [{ key: 'watch' as const, value: filters.watch, label: watchLabels[filters.watch] }] : [])
  ].map(filter => ({ ...filter, id: `${filter.key}:${filter.value}` })));

  function edit(): void {
    draft = { ...filters, genre: [...(filters.genre ?? [])], year: [...(filters.year ?? [])], resolution: [...(filters.resolution ?? [])] };
    open = true;
  }
  function select(key: Key, values: string[]): void {
    if (key === 'watch') draft = { ...draft, watch: (values[0] || undefined) as CatalogFilters['watch'] };
    else if (key === 'resolution') draft = { ...draft, resolution: values as Resolution[] };
    else draft = { ...draft, [key]: values };
  }
  function remove(ids: string[]): void {
    const removed = active.find(filter => !ids.includes(filter.id));
    if (!removed) return;
    const next = { ...filters };
    if (removed.key === 'watch') delete next.watch;
    else {
      const remaining = filters[removed.key]?.filter(value => value !== removed.value) ?? [];
      delete next[removed.key];
      if (remaining.length) return onapply({ ...next, [removed.key]: remaining });
    }
    onapply(next);
  }
</script>

<div class="filter-bar">
  <button type="button" class="btn btn--secondary btn--sm" disabled={facets === null} aria-busy={loading} aria-haspopup="dialog" aria-expanded={open} onclick={edit}>
    {t('catalog.filters')}{#if count > 0} <span aria-hidden="true">({count})</span>{/if}
  </button>
  {#if active.length}
    <Chips label={t('catalog.activeFilters')} options={active} selected={active.map(filter => filter.id)} multiple onchange={remove} />
    <button type="button" class="btn btn--secondary btn--sm" onclick={() => onapply({})}>{t('catalog.clear')}</button>
  {/if}
</div>
<ConfirmDialog bind:open title={t('catalog.filters')} confirmLabel={t('catalog.apply')} danger={false} onconfirm={() => { onapply(draft); open = false; }}>
  <p class="note">{t('catalog.countsNote')}</p>
  {#each groups as group (group.key)}
    {#if group.options.length}
      <section class="filter-group">
        <h3>{group.label}</h3>
        <Chips label={group.label} options={group.options} selected={group.key === 'watch' ? [draft.watch ?? ''] : draft[group.key] ?? []} multiple={group.key !== 'watch'} onchange={values => select(group.key, values)} />
      </section>
    {/if}
  {/each}
</ConfirmDialog>

<style>
  .filter-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 16px; min-width: 0; }
  .filter-group { min-width: 0; margin-block: 16px; }
  .filter-group h3 { margin: 0 0 4px; font-size: 14px; }
  .note { color: var(--ink-2); font-size: 13px; margin: 0; }
</style>
