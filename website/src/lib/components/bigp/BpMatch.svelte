<script lang="ts">
  import BpPoster, { type Art } from './BpPoster.svelte';
  // One title Big P proposes, drawn like the match card of the Apple TV app
  // (lib/widgets/big_p/assistant/big_p_match_card.dart): poster, title and year, kind with the
  // status label after it, a facts line and the plot.
  type Tone = 'ok' | 'requested' | 'plain';
  let {
    title,
    year,
    kind = 'Movie',
    status,
    tone = 'plain',
    facts,
    plot,
    art,
    focused = false,
  }: {
    title: string;
    year: number;
    kind?: string;
    status: string;
    tone?: Tone;
    facts?: string;
    plot: string;
    /** Which of the posters drawn for this page to show. */
    art: Art;
    /** The card the remote is on. */
    focused?: boolean;
  } = $props();
</script>

<li class="match" class:focused>
  <span class="post"><BpPoster {art} /></span>
  <div class="txt">
    <p class="t">{title} <span class="y">({year})</span></p>
    <p class="line"><span>{kind}</span><span class="pill {tone}">{status}</span></p>
    {#if facts}<p class="d">{facts}</p>{/if}
    <p class="d plot">{plot}</p>
  </div>
</li>

<style>
  .match { min-width: 0; display: flex; align-items: center; gap: 1.1rem; padding: 0.7rem 1rem 0.7rem 0.7rem; border-radius: 1.1rem; background: rgba(22, 22, 22, 0.9); transition: transform 0.5s var(--ease), background-color 0.5s var(--ease), box-shadow 0.5s var(--ease); }
  /* Focus on Apple TV: the card under the remote lifts and gets a light edge. */
  .match.focused { background: rgba(40, 40, 40, 0.92); box-shadow: 0 0 0 2px rgba(244, 241, 236, 0.9), 0 18px 40px -22px #000; transform: scale(1.015); }
  .post { position: relative; flex: none; width: 4.25rem; height: 6.25rem; border-radius: 0.5rem; overflow: hidden; box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.08); }
  .txt { flex: 1; min-width: 0; }
  .t { font-size: 1.15rem; font-weight: 700; line-height: 1.2; }
  .y { font-weight: 400; color: rgba(244, 241, 236, 0.6); }
  .line { margin-top: 0.3rem; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.3rem 0.8rem; color: rgba(244, 241, 236, 0.65); font-size: 0.9rem; }
  .pill { white-space: nowrap; padding: 0.1rem 0.8rem; border-radius: 999px; background: rgba(244, 241, 236, 0.16); color: var(--ink); font-size: 0.86rem; }
  .pill.ok { background: rgba(61, 214, 140, 0.16); color: #3dd68c; }
  .pill.requested { background: rgba(255, 176, 32, 0.16); color: var(--amber); }
  .d { margin-top: 0.25rem; color: rgba(244, 241, 236, 0.65); font-size: 0.9rem; line-height: 1.35; }
  .plot { display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  @media (max-width: 559px) {
    .match { gap: 0.8rem; }
    .t { font-size: 1.02rem; }
    .pill { white-space: normal; padding-inline: 0.65rem; font-size: 0.78rem; }
  }
</style>
