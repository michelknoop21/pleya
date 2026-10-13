<script lang="ts">
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import type { BigP } from '$lib/bigp/rig';
  import { say } from '$lib/bigp/say';
  import { onDestroy } from 'svelte';
  import Bubble from './Bubble.svelte';
  import Cta from './Cta.svelte';
  import { onCue, type Cue } from './cue';

  const goodbye = 'See you inside.';
  let bigp: BigP | undefined;
  let shown = $state(goodbye);
  let waved = false;
  let entered = false;
  let stopTalking = () => {};
  onDestroy(() => stopTalking());

  // He waves once, when the page ends: the last thing a visitor sees move.
  function wave(b: BigP) {
    if (waved) return;
    waved = true;
    b.ensure('zwaaien').then(() => b.gesture('zwaaien', 2200), () => {});
    stopTalking = say(b, goodbye, (t) => (shown = t));
  }
  // The cue fires once and can arrive before the rig does.
  function cue({ name }: Cue) {
    if (name !== 'enter') return;
    entered = true;
    if (bigp) wave(bigp);
  }
  function ready(b: BigP) {
    bigp = b;
    if (entered) wave(b);
  }
</script>

<section class="bp-close" id="join" aria-labelledby="join-title" use:onCue={cue}>
  <div class="orb red" aria-hidden="true"></div>
  <div class="wrap grid">
    <div class="host">
      <div class="say"><Bubble text={goodbye} {shown} tail="down" /></div>
      <div class="fig"><BigPFigure onready={ready} /></div>
    </div>
    <div class="copy" data-reveal>
      <h2 id="join-title">Now ask him <span class="grad">yourself.</span></h2>
      <p class="lede">Big P lives inside Pleya, which is in private beta. Join the waitlist and bring a library.</p>
      <div class="go"><Cta note /></div>
    </div>
  </div>
</section>

<style>
  .bp-close { position: relative; padding-block: var(--section) clamp(4rem, 8vw, 7rem); overflow: hidden; }
  .orb.red { width: min(70rem, 140vw); aspect-ratio: 1; left: 50%; top: 20%; transform: translateX(-50%); }
  .grid { position: relative; display: grid; gap: 2rem; justify-items: center; text-align: center; }
  .host { position: relative; width: min(60vw, 16rem); padding-top: 4.4rem; }
  .say { position: absolute; top: 0; left: 50%; width: max-content; transform: translateX(-50%); }
  h2 { font-family: var(--display); font-size: clamp(2.8rem, 8vw, 6rem); line-height: 0.92; letter-spacing: -0.04em; font-weight: 800; }
  .lede { margin: 1.4rem auto 0; max-width: 30rem; }
  .go { margin-top: 2rem; display: grid; justify-items: center; gap: 0.2rem; }
  .go :global(.bp-note) { text-align: center; }
  @media (min-width: 900px) {
    .grid { grid-template-columns: minmax(0, 20rem) minmax(0, 1fr); gap: 4rem; align-items: end; justify-items: start; text-align: left; }
    .host { width: 100%; }
    .lede { margin-inline: 0; }
    .go { justify-items: start; }
    .go :global(.bp-note) { text-align: left; }
  }
</style>
