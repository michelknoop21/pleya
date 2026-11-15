<!--
  Eén aflevering in de lijst van een seizoen: beeld met voortgang, nummer en
  titel, duur en kijkstand, de beschrijving, en rechts gezien aan of uit plus
  het kaartmenu.

  Het beeld start de speler als de server kan afspelen en de aflevering een
  versie heeft; anders is het de link naar de detailpagina. De titel gaat
  altijd naar de detailpagina, waar versies en sporen staan.
-->
<script lang="ts">
  import Artwork from '../Artwork.svelte';
  import CardMenu from '../CardMenu.svelte';
  import { describeError } from '../../api/errors';
  import { personalApi } from '../../api/personal';
  import type { Item } from '../../api/types';
  import { t } from '../../i18n';
  import { playerHref } from '../../player/route';
  import { session } from '../../stores/session.svelte';
  import { formatDuration, itemProgress } from '../../util/format';

  interface Props {
    item: Item;
    eager?: boolean;
    onchange: (patch: Partial<Item>) => void;
  }
  let { item, eager = false, onchange }: Props = $props();

  let busy = $state(false);
  let error = $state('');

  const watched = $derived(!!item.user_state?.watched);
  const progress = $derived(itemProgress(item));
  const detailHref = $derived(`/items/${encodeURIComponent(item.id)}`);
  const playable = $derived(session.capabilities?.playback_plan === true && (item.versions?.length ?? 0) > 0);
  const playHref = $derived(playable ? playerHref(item.id, progress ? item.user_state?.position_ms : undefined) : detailHref);
  const heading = $derived(
    typeof item.index === 'number' ? `${item.index}. ${item.title}` : item.title
  );
  const meta = $derived(
    [
      formatDuration(item.duration_ms),
      watched ? t('card.watched').toLowerCase() : null,
      progress ? t('card.remaining', { duration: formatDuration(progress.remainingMs) ?? '' }) : null
    ].filter(Boolean).join(' · ')
  );

  async function toggle(): Promise<void> {
    if (busy) return;
    busy = true;
    error = '';
    try {
      onchange({ user_state: await personalApi(session.client).setWatched(item.id, !watched, item.duration_ms ?? undefined) });
    } catch (err) {
      error = describeError(err);
    } finally {
      busy = false;
    }
  }
</script>

<li class="ep">
  <a class="ep__art" href={playHref} aria-label={playable ? t('card.play', { title: item.title }) : item.title}>
    <Artwork artworkId={item.artwork?.backdrop_id ?? item.artwork?.poster_id} alt="" shape="wide" {eager} />
    {#if playable}
      <span class="ep__play" aria-hidden="true"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg></span>
    {/if}
    {#if progress || watched}
      <span class="ep__prog" aria-hidden="true"><i style:width="{watched ? 100 : (progress?.fraction ?? 0) * 100}%"></i></span>
    {/if}
  </a>
  <div class="ep__text">
    <a class="ep__title" href={detailHref}>{heading}</a>
    {#if meta}<div class="ep__meta">{meta}</div>{/if}
    {#if item.summary?.trim()}<p class="ep__summary">{item.summary}</p>{/if}
    {#if error}<p class="ep__meta" role="alert">{error}</p>{/if}
  </div>
  <div class="ep__acts">
    {#if session.capabilities?.watch_state === true}
      <button type="button" class="ep__ico" aria-pressed={watched} aria-disabled={busy} aria-label={t('series.watchedToggle', { title: item.title })} onclick={toggle}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><path d="m5 12 5 5 9-10" /></svg>
      </button>
    {/if}
    <CardMenu {item} {onchange} />
  </div>
</li>

<style>
  .ep {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 14px 20px;
    padding: 16px 0;
    border-top: 1px solid var(--hairline);
  }
  .ep__art {
    position: relative;
    flex: none;
    width: 224px;
    aspect-ratio: 16 / 9;
    border-radius: var(--radius-md);
    overflow: hidden;
    background: var(--panel);
    color: var(--art-ink);
  }
  .ep__art :global(.artwork) { height: 100%; }
  .ep__play {
    position: absolute;
    inset: 0;
    margin: auto;
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: 50%;
    border: 1px solid color-mix(in srgb, var(--art-ink) 30%, transparent);
    background: color-mix(in srgb, var(--art-shade) 50%, transparent);
  }
  .ep__play svg { width: 20px; height: 20px; }
  .ep__prog { position: absolute; left: 0; right: 0; bottom: 0; height: 4px; background: color-mix(in srgb, var(--art-shade) 50%, transparent); }
  .ep__prog i { display: block; height: 100%; background: var(--accent); }
  .ep__text { flex: 999 1 320px; min-width: 0; }
  .ep__title { font-size: 17px; font-weight: 700; color: var(--ink); overflow-wrap: anywhere; }
  .ep__meta { margin: 2px 0 6px; font-size: 13px; color: var(--ink-2); }
  .ep__summary { margin: 0; max-width: 680px; color: var(--ink-2); overflow-wrap: anywhere; }
  .ep__acts { display: flex; align-items: center; gap: 12px; }
  .ep__ico,
  .ep__acts :global(button.more) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 48px;
    height: 48px;
    padding: 0;
    border: 1px solid color-mix(in srgb, var(--text) 30%, transparent);
    border-radius: 50%;
    background: color-mix(in srgb, var(--bg) 50%, transparent);
    color: var(--ink);
    cursor: pointer;
  }
  .ep__ico svg { width: 20px; height: 20px; }
  .ep__ico[aria-pressed='true'] { background: var(--ink); border-color: var(--ink); color: var(--bg); }
  .ep__ico[aria-disabled='true'] { opacity: 0.5; cursor: progress; }
  @media (hover: hover) {
    .ep__title:hover { text-decoration: underline; }
  }
  @media (max-width: 599px) {
    .ep__art { width: 132px; }
    .ep__text { flex-basis: 120px; }
    .ep__summary { display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
    .ep__acts { width: 100%; justify-content: flex-end; margin-top: -6px; }
    .ep__ico, .ep__acts :global(button.more) { width: 44px; height: 44px; }
  }
</style>
