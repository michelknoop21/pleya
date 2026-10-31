<!--
  De rijen van scherm 18: nummer, poster, titel met onderregel, kijkstatus en een
  menu. Een wit vinkje voor uitgekeken, een percentagepil voor onderweg, niets
  voor ongezien. Op smal blijft dezelfde rij staan; de onderregel kapt af.
-->
<script lang="ts">
  import Artwork from '../Artwork.svelte';
  import ActionMenu from './ActionMenu.svelte';
  import type { Item } from '../../api/types';
  import { addToList } from '../../stores/addToList.svelte';
  import { session } from '../../stores/session.svelte';
  import { goto } from '$app/navigation';
  import { isWatched } from '../../util/format';
  import { t } from '../../i18n';
  import { rowMeta, rowPercent } from './listText';

  let { items, numbered = true, onremove }: { items: Item[]; numbered?: boolean; onremove?: (item: Item) => void } = $props();

  const canAdd = $derived(session.capabilities?.collections === true || session.capabilities?.playlists === true);

  function actions(item: Item) {
    return [
      { label: t('lists.open'), onselect: () => void goto(`/items/${encodeURIComponent(item.id)}`) },
      ...(canAdd ? [{ label: t('lists.add.title'), onselect: () => addToList.open(item) }] : []),
      ...(onremove ? [{ label: t('lists.removeItem'), danger: true, onselect: () => onremove(item) }] : [])
    ];
  }
</script>

<ol class="rows">
  {#each items as item, index (item.id)}
    {@const percent = rowPercent(item)}
    <li class="row" data-item-id={item.id}>
      {#if numbered}<span class="row__n">{index + 1}</span>{/if}
      <a class="row__link" href="/items/{item.id}">
        <span class="row__art"><Artwork artworkId={item.artwork?.poster_id} alt="" shape="poster" /></span>
        <span class="row__text">
          <span class="row__title">{item.title}</span>
          <span class="row__meta">{rowMeta(item)}</span>
        </span>
      </a>
      {#if isWatched(item)}
        <span class="row__watched" role="img" aria-label={t('card.watched')}>
          <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5" /></svg>
        </span>
      {:else if percent !== null}
        <span class="row__percent">{percent}%</span>
      {/if}
      <ActionMenu label={t('lists.moreFor', { title: item.title })} actions={actions(item)} size="plain" />
    </li>
  {/each}
</ol>

<style>
  .rows {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    list-style: none;
    overflow: hidden;
    border-radius: var(--radius-card);
    background: var(--panel);
  }

  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 84px;
    padding: 12px;
  }

  .row + .row {
    box-shadow: inset 0 1px 0 var(--hairline);
  }

  .row__n {
    flex: none;
    width: 28px;
    text-align: center;
    font-size: 14px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .row__link {
    display: flex;
    flex: 1;
    align-items: center;
    gap: 14px;
    min-width: 0;
    color: inherit;
    text-decoration: none;
  }

  .row__link:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 2px;
    border-radius: var(--radius-sm);
  }

  .row__art {
    flex: none;
    width: 40px;
    overflow: hidden;
    border-radius: var(--radius-sm);
    background: var(--inset-bg);
  }

  .row__text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .row__title,
  .row__meta {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .row__title {
    font-size: 15px;
    color: var(--ink);
  }

  .row__meta {
    font-size: 13px;
    color: var(--ink-3);
  }

  .row__watched {
    display: inline-flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--ink);
    color: var(--bg);
  }

  .row__percent {
    flex: none;
    padding: 3px 10px;
    border-radius: 999px;
    background: var(--elevated);
    font-size: 13px;
    font-weight: 600;
    color: var(--ink);
    font-variant-numeric: tabular-nums;
  }

  @media (max-width: 479px) {
    .row {
      gap: 8px;
      padding: 10px 6px 10px 10px;
    }

    .row__n {
      width: 20px;
    }

    .row__link {
      gap: 10px;
    }
  }
</style>
