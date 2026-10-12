<script lang="ts">
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import type { BigP } from '$lib/bigp/rig';
  import { onCue, type Cue } from './cue';

  let bigp: BigP | undefined;

  // Big P points at the card that is being read: the one under the pointer, otherwise the one the page motion reports as it scrolls into the middle of the window.
  const point = (el: Element) => bigp?.follow(el);
  function cue({ name, el }: Cue) {
    if (name === 'card' && el) point(el);
    if (name === 'leave') bigp?.aimAt(null);
  }
  const pointer = (e: Event) => point(e.currentTarget as Element);
</script>

<section class="bp-section bento" id="can" aria-labelledby="can-title" use:onCue={cue}>
  <div class="orb red" aria-hidden="true"></div>
  <div class="wrap">
    <div class="top">
      <div class="fig"><BigPFigure onready={(b) => (bigp = b)} /></div>
      <div class="bp-head" data-reveal>
        <h2 id="can-title" data-split>Four more things he does.</h2>
      </div>
    </div>

    <ul class="grid">
      <li class="bz" data-card onpointerenter={pointer}>
        <article class="bz-core">
          <h3>A filter for the kids</h3>
          <p>Set the children's ages on a profile and Big P only shows titles that suit them. The ages stay on that device, with that profile.</p>
          <div class="live ages" aria-hidden="true">
            <span class="tag on">6 years</span><span class="tag on">9 years</span>
            <span class="tag">All</span><span class="tag">6</span><span class="tag">9</span><span class="tag out">12</span><span class="tag out">16</span>
          </div>
        </article>
      </li>
      <li class="bz" data-card onpointerenter={pointer}>
        <article class="bz-core">
          <h3>Request what is missing</h3>
          <p>Not in your library? Big P looks it up in Seerr, by title or by description, and sends the request once you confirm.</p>
          <div class="live flow" aria-hidden="true">
            <span class="tag">Requestable</span><span class="arrow"></span><span class="tag on">Request sent</span>
          </div>
        </article>
      </li>
      <li class="bz" data-card onpointerenter={pointer}>
        <article class="bz-core">
          <h3>Library Doctor</h3>
          <p>A check-up for a library. It reports copies of the same title, aired episodes you are missing and gaps in the metadata.</p>
          <ul class="live doctor" aria-hidden="true">
            <li><b>2</b>copies of one film</li>
            <li><b>1</b>aired episode missing</li>
            <li><b>3</b>metadata fields empty</li>
          </ul>
        </article>
      </li>
      <li class="bz" data-card onpointerenter={pointer}>
        <article class="bz-core">
          <h3>Playback, subtitles, downloads</h3>
          <p>Switch the audio or subtitle track while you watch, or fetch a subtitle that is missing. Going offline? Ask for the next episodes.</p>
          <div class="live play" aria-hidden="true">
            <span>Subtitles</span><span class="tag on">English</span>
            <span>Next 3 episodes</span><span class="bar"><i></i></span>
          </div>
        </article>
      </li>
    </ul>
  </div>
</section>

<style>
  .orb.red { width: min(60rem, 120vw); aspect-ratio: 1; right: -25%; top: 8%; }
  .wrap { position: relative; }
  .top { display: grid; gap: 0.5rem; align-items: end; }
  .fig { width: 8.5rem; margin-bottom: -1.2rem; }
  .grid { margin-top: 2.5rem; display: grid; gap: 1rem; }
  /* The page motion owns the transform of the tray, so the hover lift goes on the card inside it. */
  .bz { transition: background-color 0.7s var(--ease); }
  .bz:hover { background: rgba(255, 255, 255, 0.07); }
  .bz-core { display: flex; flex-direction: column; transition: transform 0.7s var(--ease); }
  .bz:hover .bz-core { transform: translateY(-3px); }
  h3 { font-family: var(--display); font-size: clamp(1.35rem, 2vw, 1.7rem); line-height: 1.12; letter-spacing: -0.02em; }
  p { margin-top: 0.7rem; color: var(--muted); font-size: 0.98rem; line-height: 1.55; max-width: 34rem; }
  .live { margin-top: auto; padding-top: 1.6rem; display: flex; flex-wrap: wrap; align-items: center; gap: 0.45rem; font-size: 0.86rem; color: var(--muted); }
  .arrow { width: 1.6rem; height: 1px; background: linear-gradient(90deg, transparent, var(--amber)); }



  .ages .tag.on:nth-child(2) { margin-right: 0.7rem; }
  .ages .out { opacity: 0.35; text-decoration: line-through; }
  .flow .on { animation: token 4.5s var(--ease) infinite 0.6s; }

  .doctor { display: grid; gap: 0.5rem; align-items: stretch; }
  .doctor li { display: flex; align-items: baseline; gap: 0.6rem; }
  .doctor b { min-width: 1.1rem; font-family: var(--display); font-size: 1.15rem; color: var(--amber); }
  .play { display: grid; grid-template-columns: 1fr auto; gap: 0.6rem 1rem; }
  .play .bar { width: 5.5rem; height: 0.35rem; align-self: center; border-radius: 999px; background: rgba(255, 255, 255, 0.12); overflow: hidden; }
  .play .bar i { display: block; height: 100%; background: var(--brand); transform-origin: left; animation: load 4s var(--ease) infinite; }

  @keyframes token { 0%, 12% { opacity: 0.25; transform: translateY(3px); } 24%, 100% { opacity: 1; transform: none; } }
  @keyframes load { 0% { transform: scaleX(0); } 70%, 100% { transform: scaleX(1); } }

  @media (min-width: 700px) {
    .grid { grid-template-columns: repeat(12, minmax(0, 1fr)); }
    .grid > li { grid-column: span 6; }
    .top { grid-template-columns: auto 1fr; gap: 1.5rem; }
    .fig { width: 11rem; margin-bottom: -2.2rem; }
  }
  @media (min-width: 1024px) {
    .grid > li:nth-child(4n + 1), .grid > li:nth-child(4n) { grid-column: span 7; }
    .grid > li:nth-child(4n + 2), .grid > li:nth-child(4n + 3) { grid-column: span 5; }
    .fig { width: 13rem; }
  }
</style>
