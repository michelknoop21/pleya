<script lang="ts">
  import ChevronIcon from '~icons/material-symbols-light/chevron-right-rounded';
  import BpPoster, { type Art } from './BpPoster.svelte';
  // One title Big P proposes, drawn like the title card of the app
  // (lib/widgets/big_p/assistant/big_p_match_card.dart): poster, title and year, kind and
  // runtime, the status label, and on a wide screen a line of plot.
  type Tone = 'ok' | 'plain';
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
    /** The card that has the focus. */
    focused?: boolean;
  } = $props();
</script>

<li class="match" class:focused>
  <span class="post"><BpPoster {art} /></span>
  <div class="txt">
    <p class="t">{title} <span class="y">({year})</span></p>
    <p class="d">{facts ? `${kind} · ${facts}` : kind}</p>
    <p class="plot">{plot}</p>
    <p><span class="pill {tone}">{status}</span></p>
  </div>
  <ChevronIcon aria-hidden="true" />
</li>

<style>
  .match { min-width: 0; display: flex; align-items: center; gap: 0.9rem; padding: 0.7rem 0.6rem 0.7rem 0.7rem; border-radius: 1.1rem; background: rgba(22, 22, 22, 0.92); }
  /* Focus as the app shows it: a light edge around the card the remote or the finger is on. */
  .match.focused { box-shadow: 0 0 0 2px rgba(244, 241, 236, 0.9); }
  .post { flex: none; width: 4rem; height: 5.9rem; border-radius: 0.5rem; overflow: hidden; box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.08); }
  .txt { flex: 1; min-width: 0; display: grid; gap: 0.25rem; }
  .t { font-size: 1.08rem; font-weight: 700; line-height: 1.2; }
  .y { font-weight: 400; color: rgba(255, 255, 255, 0.65); }
  .d, .plot { color: rgba(255, 255, 255, 0.65); font-size: 0.9rem; line-height: 1.35; }
  .plot { display: none; }
  .pill { display: inline-block; margin-top: 0.15rem; padding: 0.18rem 0.75rem; border-radius: 999px; background: rgba(255, 255, 255, 0.12); color: var(--ink); font-size: 0.84rem; line-height: 1.3; }
  .pill.ok { background: rgba(61, 214, 140, 0.16); color: #3dd68c; }
  .match > :global(svg) { flex: none; font-size: 1.6rem; color: rgba(255, 255, 255, 0.65); }
  @media (min-width: 900px) {
    .plot { display: -webkit-box; -webkit-line-clamp: 1; line-clamp: 1; -webkit-box-orient: vertical; overflow: hidden; }
  }
</style>
