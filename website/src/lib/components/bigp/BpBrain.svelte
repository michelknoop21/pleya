<script lang="ts">
  import OllamaIcon from '~icons/simple-icons/ollama';
  import OpenRouterIcon from '~icons/simple-icons/openrouter';
  import RouterIcon from '~icons/material-symbols-light/router-outline';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import type { BigP } from '$lib/bigp/rig';
  import Bubble from './Bubble.svelte';
  import Cta from './Cta.svelte';
  import { onCue, type Cue } from './cue';

  // What Big P says on the question screen while no model is set up.
  const empty = "I don't have a brain yet.";
  const offer = 'Pick one and I am ready.';
  let bigp: BigP | undefined;
  let line = $state(empty);

  function ready(b: BigP) {
    bigp = b;
    // The cue can arrive before the rig does.
    if (line === empty) b.set('worried');
  }
  // The providers scroll into view: he cheers up.
  function cue({ name }: Cue) {
    if (name !== 'enter' || line === offer) return;
    line = offer;
    bigp?.react();
    bigp?.settle(2000);
  }

  // Names and descriptions as the Big P settings show them; `needs` is what you fill in there.
  const providers = [
    { icon: RouterIcon, name: 'Ollama server', text: 'Runs on your own network, for example on your NAS.', needs: 'You enter the server address. The model runs on hardware you already own.' },
    { icon: OllamaIcon, name: 'Ollama Cloud', text: 'Models that Ollama runs for you.', needs: 'You enter an API key from your Ollama account.' },
    { icon: OpenRouterIcon, name: 'OpenRouter', text: 'One key for models from several vendors.', needs: 'You enter an OpenRouter key. The model list marks each model as free, low cost, mid-priced or expensive.' },
  ];
</script>

<section class="bp-section brain" id="brain" aria-labelledby="brain-title">
  <div class="orb amber" aria-hidden="true"></div>
  <div class="wrap">
    <div class="top">
      <div class="host">
        <div class="say"><Bubble text={line} tail="down" /></div>
        <div class="fig"><BigPFigure onready={ready} /></div>
      </div>
      <div class="bp-head" data-reveal>
        <h2 id="brain-title" data-split>He needs a language model. You choose which.</h2>
        <p class="lede">
          Pleya does not ship a language model and does not run one itself. Open Big P in the app, start the setup and
          pick one of these three. Pleya fetches the models, lists only the ones that can call Pleya's functions, and
          lets you test the connection.
        </p>
      </div>
    </div>

    <dl class="providers" use:onCue={cue}>
      {#each providers as p (p.name)}
        <div>
          <dt><p.icon aria-hidden="true" />{p.name}</dt>
          <dd>{p.text}</dd>
          <dd class="needs">{p.needs}</dd>
        </div>
      {/each}
    </dl>

    <div class="quotes" data-reveal>
      <figure>
        <figcaption>What leaves your device</figcaption>
        <blockquote>
          Your question goes to the provider, with the names of libraries, servers and users needed to answer it.
          Passwords and tokens stay in Pleya.
        </blockquote>
      </figure>
      <figure>
        <figcaption>The switch "Add online information"</figcaption>
        <blockquote>
          Big P then adds the age rating, genres, runtime, cast, score and streaming services of a title from online
          film databases. Only the title or the title's ids go to those services, never your account or profile. With
          the switch off, Big P uses only your server and Seerr.
        </blockquote>
      </figure>
    </div>
    <p class="example">The first note is quoted from the Big P settings in the app. The second is shortened: the app names each database.</p>
    <div class="bp-next"><Cta note /></div>
  </div>
</section>

<style>
  .orb.amber { width: min(50rem, 110vw); aspect-ratio: 1; right: -18%; top: -6%; }
  .wrap { position: relative; }
  .top { display: grid; gap: 2rem; align-items: end; }
  .host { position: relative; width: min(56vw, 14rem); padding-top: 4.6rem; }
  .say { position: absolute; top: 0; left: 50%; width: max-content; max-width: min(80vw, 16rem); transform: translateX(-50%); }
  /* Three rows, not three cards: name, what it is, what you fill in. */
  .providers { margin-top: 3rem; display: grid; }
  .providers div { display: grid; gap: 0.35rem; padding-block: 1.5rem; border-top: 1px solid var(--hair); }
  dt { display: flex; align-items: center; gap: 0.8rem; font-family: var(--display); font-size: clamp(1.4rem, 2.4vw, 1.9rem); font-weight: 600; letter-spacing: -0.02em; }
  dt :global(svg) { flex: none; font-size: 0.9em; color: var(--amber); }
  dd { max-width: 34rem; color: var(--muted); line-height: 1.55; }
  dd.needs { color: var(--ink); }
  .quotes { margin-top: 3.5rem; display: grid; gap: 2.5rem; }
  figcaption { color: var(--muted); font-size: 0.9rem; font-weight: 600; }
  blockquote { margin: 0.6rem 0 0; max-width: 36rem; color: var(--ink); font-size: clamp(1.02rem, 1.4vw, 1.18rem); line-height: 1.6; }
  .example { margin-top: 1.6rem; }
  @media (min-width: 800px) {
    .top { grid-template-columns: 15rem minmax(0, 1fr); gap: 3rem; }
    .host { width: 100%; }
    .providers div { grid-template-columns: 17rem 1fr 1fr; gap: 2.5rem; align-items: baseline; }
    .quotes { grid-template-columns: 0.8fr 1.2fr; gap: 4rem; }
  }
</style>
