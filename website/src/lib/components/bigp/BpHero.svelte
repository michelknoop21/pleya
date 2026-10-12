<script lang="ts">
  import { onDestroy } from 'svelte';
  import { cta } from '$lib/config';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import { L } from '$lib/bigp/layers';
  import type { BigP } from '$lib/bigp/rig';
  import { say } from '$lib/bigp/say';
  import Bubble from './Bubble.svelte';
  import Cta from './Cta.svelte';

  // The greeting of the question screen in the app, without the name.
  const greeting = 'Hi, what are we looking for?';
  let fig: HTMLDivElement;
  let shown = $state('');
  let arrived = $state(false);
  let stopTalking = () => {};
  onDestroy(() => stopTalking());

  // He walks in from outside the right edge of the window, waves, then says hello.
  async function enter(bigp: BigP) {
    const r = fig.getBoundingClientRect();
    await bigp.walkIn(((window.innerWidth - r.left) / r.width) * L.w + 80, 2);
    arrived = true;
    bigp.ensure('zwaaien').then(() => bigp.gesture('zwaaien', 1900), () => {});
    stopTalking = say(bigp, greeting, (t) => (shown = t));
  }
</script>

<section class="bp-hero" id="top">
  <div class="orb red" aria-hidden="true"></div>
  <div class="orb amber" aria-hidden="true"></div>
  <div class="wrap grid">
    <div class="copy">
      <p class="eyebrow">Pleya Assistant</p>
      <h1 class="hero-title">
        <span class="ln"><span>Just ask</span></span>
        <span class="ln"><span class="grad">Big P.</span></span>
      </h1>
      <p class="lede">
        Big P is the assistant inside Pleya. Describe a film you half remember or ask what to watch tonight, and he
        searches every server you have connected. He can run those servers too. For a sensitive change, such as creating
        a user, Pleya asks you first.
      </p>
      <div class="actions">
        <Cta />
        <a class="bp-more" href="#can">See what he can do</a>
      </div>
      <p class="cta-note">{cta.note}</p>
    </div>
    <div class="stage">
      <div class="say" class:arrived><Bubble text={greeting} {shown} /></div>
      <div class="fig" bind:this={fig}><BigPFigure enters onready={enter} /></div>
    </div>
  </div>
</section>

<style>
  .bp-hero { padding-top: 7.5rem; padding-bottom: 4rem; overflow: hidden; }
  .orb.red { width: min(70rem, 120vw); aspect-ratio: 1; right: -22%; top: -10%; }
  .orb.amber { width: min(40rem, 90vw); aspect-ratio: 1; left: -14%; bottom: -30%; }
  /* The orbs are cut off by the section edge: fade them out so the next section starts on black. */
  .bp-hero::after { content: ''; position: absolute; inset: auto 0 0; height: 9rem; background: linear-gradient(transparent, #000); pointer-events: none; }
  .grid { position: relative; z-index: 1; display: grid; gap: 2rem; }
  .eyebrow { margin-bottom: 1.4rem; }
  .bp-hero .hero-title { font-size: clamp(3.4rem, 10vw, 7.4rem); }
  .bp-hero .lede { margin-top: 1.8rem; max-width: 33rem; }
  .actions { margin-top: 2.2rem; display: flex; flex-wrap: wrap; align-items: center; gap: 0.6rem 1.6rem; }
  .stage { position: relative; padding-top: 4.5rem; }
  .fig { width: min(78vw, 22rem); margin-inline: auto; }
  .say { position: absolute; z-index: 1; left: 0; top: 0; opacity: 0; transform: translateY(10px) scale(0.96); transform-origin: 80% 100%; transition: opacity 0.5s var(--ease), transform 0.7s var(--ease); }
  .say.arrived { opacity: 1; transform: none; }
  @media (min-width: 900px) {
    .bp-hero { min-height: min(100dvh, 58rem); display: grid; align-items: center; padding-bottom: 5rem; }
    .grid { grid-template-columns: minmax(0, 1.08fr) minmax(0, 0.92fr); align-items: center; gap: 3rem; }
    .stage { padding-top: 3rem; }
    .fig { width: min(100%, 29rem); margin-inline: auto 4%; }
    .say { left: 2%; top: 1.5rem; }
  }
  @media (prefers-reduced-motion: reduce) {
    .say { opacity: 1; transform: none; }
  }
</style>
