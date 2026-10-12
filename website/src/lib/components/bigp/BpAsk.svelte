<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import { prefersReducedMotion } from '$lib/bigp/loop';
  import type { BigP } from '$lib/bigp/rig';
  import { say } from '$lib/bigp/say';
  import sintel from '$lib/assets/bigp/posters/sintel.webp';
  import spring from '$lib/assets/bigp/posters/spring.webp';
  import charge from '$lib/assets/bigp/posters/charge.webp';
  import Bubble from './Bubble.svelte';
  import BpMatch from './BpMatch.svelte';
  import Cta from './Cta.svelte';

  // The first question is one of the app's own examples; the other two and all answers are written for this page.
  const asks = [
    { id: 'tonight', q: 'What can I watch tonight?', step: 'Checking what you watched', line: 'Three from your library you have not seen yet.' },
    { id: 'plot', q: 'That movie where an astronaut is stranded on Mars and grows potatoes', step: 'Finding the title', line: 'That sounds like The Martian.' },
    { id: 'story', q: 'Who is Anna? No spoilers.', step: 'Checking what you watched', line: 'You are at episode 3, so I stop there.' },
  ] as const;
  // Blender open movies: the only artwork this page may show.
  const tonight = [
    { poster: sintel, title: 'Sintel', year: 2010, facts: '15m · Animation · Fantasy', plot: 'A young woman searches for the dragon she raised.' },
    { poster: spring, title: 'Spring', year: 2019, facts: '8m · Animation · Fantasy', plot: 'A shepherd girl and her dog face old spirits to keep the seasons turning.' },
    { poster: charge, title: 'Charge', year: 2022, facts: '4m · Animation · Sci-fi', plot: 'An old man breaks into a battery factory with a security droid on his heels.' },
  ];
  const idleLine = 'Pick a question.';

  type Phase = 'idle' | 'listening' | 'working' | 'answer';
  let bigp: BigP | undefined;
  let phase = $state<Phase>('idle');
  let active = $state<(typeof asks)[number] | null>(null);
  let typed = $state('');
  let said = $state(idleLine);
  let timers: ReturnType<typeof setTimeout>[] = [];
  let stopTalking = () => {};
  let matches = $state<HTMLElement>();

  const line = $derived(phase === 'listening' ? "I'm listening…" : phase === 'working' ? 'Let me check…' : phase === 'answer' && active ? active.line : idleLine);

  function clear() {
    timers.forEach(clearTimeout);
    timers = [];
    stopTalking();
    bigp?.aimAt(null);
  }
  onDestroy(clear);

  // Listening, working, answering: the same three beats the app shows, on a fixed script.
  function ask(a: (typeof asks)[number]) {
    clear();
    const quick = prefersReducedMotion();
    active = a;
    phase = 'listening';
    said = "I'm listening…";
    bigp?.set('listening');
    const per = quick ? 0 : Math.min(26, 1100 / a.q.length);
    typed = quick ? a.q : '';
    for (let i = 1; i <= a.q.length && !quick; i++) timers.push(setTimeout(() => (typed = a.q.slice(0, i)), i * per));
    const heard = a.q.length * per + (quick ? 250 : 450);
    timers.push(
      setTimeout(() => {
        phase = 'working';
        said = 'Let me check…';
        bigp?.set('working');
        bigp?.nod(0.7);
      }, heard),
      setTimeout(() => {
        phase = 'answer';
        if (!bigp) return void (said = a.line);
        bigp.set('success');
        bigp.hop(70, 0.55);
        stopTalking = say(bigp, a.line, (t) => (said = t), () => bigp?.settle(1400));
        // His suggestions are on screen: he points at the first one, as he does in the app.
        if (a.id !== 'story') tick().then(() => timers.push(setTimeout(() => matches?.firstElementChild && bigp?.aimAt(matches.firstElementChild), 1300)));
      }, heard + (quick ? 350 : 1500)),
    );
  }
</script>

<section class="bp-section ask" id="ask" aria-labelledby="ask-title">
  <div class="orb amber" aria-hidden="true"></div>
  <div class="wrap">
    <div class="bp-head" data-reveal>
      <p class="eyebrow">Try him</p>
      <h2 id="ask-title" data-split>Ask the way you would say it.</h2>
      <p class="lede">
        Pick one of these. They are the kind of question you ask in the app. The answers on this page are scripted:
        there is no language model behind them.
      </p>
    </div>

    <div class="demo">
      <div class="host">
        <div class="say"><Bubble text={line} shown={said} tail="down" /></div>
        <div class="fig"><BigPFigure onready={(b) => (bigp = b)} /></div>
      </div>

      <div class="bz panel">
        <div class="bz-core">
          <p class="bar" class:busy={phase === 'listening'}>
            <span class="label">Example question</span>
            <span class:placeholder={!typed}>{typed || 'Pick one below.'}</span>
          </p>
          <ul class="chips">
            {#each asks as a (a.id)}
              <li><button type="button" aria-pressed={active?.id === a.id} onclick={() => ask(a)}>{a.q}</button></li>
            {/each}
          </ul>

          <div class="out" aria-live="polite">
            {#if phase === 'working' && active}
              <p class="step"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>{active.step}</p>
            {:else if phase === 'answer' && active}
              {#key active.id}
                <div class="answer">
                  {#if active.id === 'tonight'}
                    <p class="asked"><span>You asked:</span> {active.q}</p>
                    <p class="title">Three you have not seen yet.</p>
                    <ul class="matches" bind:this={matches}>
                      {#each tonight as m, i (m.title)}
                        <BpMatch focused={i === 0} status="In your library · Home server" tone="ok" {...m} />
                      {/each}
                    </ul>
                  {:else if active.id === 'plot'}
                    <p class="asked"><span>You asked:</span> {active.q}</p>
                    <p class="title">That sounds like The Martian.</p>
                    <p class="body">You never said the title. Big P matched what happens in the film.</p>
                    <ul class="matches" bind:this={matches}>
                      <BpMatch focused title="The Martian" year={2015} status="In your library · Home server" tone="ok" facts="2h 24m · Sci-fi · Adventure" plot="Astronaut Mark Watney is left behind on Mars and has to survive until help arrives." />
                      <BpMatch title="Mission to Mars" year={2000} kind="Movie · possibly" status="Already requested" tone="requested" tint="#1d2a3a, #5a7fa8" plot="A rescue mission looks for the first crew that vanished on Mars." />
                      <BpMatch title="Red Planet" year={2000} kind="Movie · possibly" status="Requestable" tint="#3a1612, #a8402e" plot="A crew is stranded on Mars and has to find its own way back." />
                    </ul>
                  {:else}
                    <p class="asked"><span>You asked:</span> {active.q}</p>
                    <p class="title">Anna is the harbour pilot.</p>
                    <p class="body">She found the logbook in episode 1 and does not trust the captain yet. That is all I can say at S1 E3 of TIDE, where you are.</p>
                    <p class="meta"><span class="tag on">Stops at what you have watched</span></p>
                  {/if}
                </div>
              {/key}
            {:else if phase === 'idle'}
              <p class="step idle">The answer appears here.</p>
            {/if}
            {#if phase === 'answer' && active && active.id !== 'story'}
              <p class="shown">Drawn after the Apple TV app: the card with the light edge is where the remote is.</p>
            {/if}
          </div>
        </div>
      </div>
    </div>
    <p class="example">
      Scripted example. TIDE is a demo title; the posters are Blender open movies, see the <a href="/media-credits.html">media credits</a>.
    </p>
    <div class="bp-next"><Cta note /></div>
  </div>
</section>

<style>
  .orb.amber { width: min(46rem, 100vw); aspect-ratio: 1; left: -18%; top: 20%; }
  .wrap { position: relative; }
  .demo { margin-top: 3.5rem; display: grid; gap: 1.5rem; align-items: end; }
  .host { position: relative; width: min(60vw, 15rem); margin-inline: auto; padding-top: 4.8rem; }
  .say { position: absolute; top: 0; left: 50%; width: max-content; max-width: min(84vw, 17rem); transform: translateX(-50%); }
  /* A line of transcript, not a field: nothing on this page takes typed input. */
  .bar { display: grid; gap: 0.3rem; min-height: 4.2rem; padding-left: 1rem; border-left: 2px solid var(--hair); font-size: 1.15rem; line-height: 1.35; transition: border-color 0.5s var(--ease); }
  .bar.busy { border-left-color: var(--amber); }
  .label { color: var(--amber); font-size: 0.72rem; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; }
  .placeholder { color: var(--faint); }
  .chips { margin-top: 1rem; display: flex; flex-wrap: wrap; gap: 0.55rem; }
  .chips button { min-height: 44px; padding: 0.55rem 1rem; border-radius: 1.4rem; background: rgba(255, 255, 255, 0.05); box-shadow: inset 0 0 0 1px var(--hair); color: var(--muted); font-size: 0.93rem; line-height: 1.3; text-align: left; transition: background-color 0.4s var(--ease), color 0.4s var(--ease), transform 0.4s var(--ease); }
  .chips button:hover { background: rgba(255, 255, 255, 0.1); color: var(--ink); }
  .chips button:active { transform: scale(0.98); }
  .chips button[aria-pressed='true'] { background: rgba(255, 176, 32, 0.14); box-shadow: inset 0 0 0 1px rgba(255, 176, 32, 0.4); color: var(--ink); }
  .out { margin-top: 1.4rem; min-height: 15.5rem; padding-top: 1.4rem; border-top: 1px solid var(--hair); }
  .step { display: flex; align-items: center; gap: 0.7rem; color: var(--muted); }
  .step.idle { color: var(--faint); }
  .dots { display: inline-flex; gap: 0.25rem; }
  .dots i { width: 0.36rem; height: 0.36rem; border-radius: 50%; background: var(--amber); animation: dot 1s var(--ease) infinite; }
  .dots i:nth-child(2) { animation-delay: 0.15s; }
  .dots i:nth-child(3) { animation-delay: 0.3s; }
  .answer { animation: rise 0.7s var(--ease) both; }
  .title { margin-top: 0.6rem; font-family: var(--display); font-size: clamp(1.8rem, 3vw, 2.4rem); font-weight: 700; letter-spacing: -0.02em; line-height: 1.1; }
  .meta { margin-top: 0.8rem; display: flex; flex-wrap: wrap; gap: 0.4rem; }
  .body { margin-top: 0.8rem; max-width: 30rem; color: var(--muted); font-size: 1.02rem; line-height: 1.55; }
  .asked { color: var(--muted); font-size: 0.95rem; }
  .asked span { color: var(--faint); }
  .matches { margin-top: 1.2rem; display: grid; gap: 0.6rem; }
  .shown { margin-top: 0.9rem; color: var(--muted); font-size: 0.82rem; }
  .example { margin-top: 1.4rem; }
  @keyframes dot { 0%, 100% { opacity: 0.3; transform: translateY(0); } 40% { opacity: 1; transform: translateY(-3px); } }
  @keyframes rise { from { opacity: 0; transform: translateY(14px); } }
  @media (min-width: 900px) {
    .demo { grid-template-columns: minmax(0, 17rem) minmax(0, 1fr); gap: 2.5rem; }
    .host { width: 100%; }
    .example, .bp-next { margin-left: 19.5rem; }
  }
</style>
