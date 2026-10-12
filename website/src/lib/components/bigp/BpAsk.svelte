<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import { prefersReducedMotion } from '$lib/bigp/loop';
  import type { BigP } from '$lib/bigp/rig';
  import { say } from '$lib/bigp/say';
  import { groups, type Ask } from './asks';
  import Bubble from './Bubble.svelte';
  import BpMatch from './BpMatch.svelte';
  import BpRows from './BpRows.svelte';
  import Cta from './Cta.svelte';

  const idleLine = 'Pick a question.';

  type Phase = 'idle' | 'listening' | 'working' | 'answer';
  let bigp: BigP | undefined;
  let phase = $state<Phase>('idle');
  let active = $state<Ask | null>(null);
  let typed = $state('');
  let said = $state(idleLine);
  let timers: ReturnType<typeof setTimeout>[] = [];
  let stopTalking = () => {};
  let out = $state<HTMLElement>();

  const line = $derived(phase === 'listening' ? "I'm listening…" : phase === 'working' ? 'Let me check…' : phase === 'answer' && active ? active.line : idleLine);

  function clear() {
    timers.forEach(clearTimeout);
    timers = [];
    stopTalking();
    bigp?.aimAt(null);
  }
  onDestroy(clear);

  // The answer may open below the window: bring it in, without moving a page that already shows it.
  const reveal = () => out?.scrollIntoView({ block: 'nearest', behavior: prefersReducedMotion() ? 'auto' : 'smooth' });

  // Listening, working, answering: the same three beats the app shows, on a fixed script.
  function ask(a: Ask) {
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
        tick().then(reveal);
        if (!bigp) return void (said = a.line);
        bigp.set('success');
        bigp.hop(70, 0.55);
        stopTalking = say(bigp, a.line, (t) => (said = t), () => bigp?.settle(1400));
        // What he found is on screen: he points at the first card, as he does in the app.
        timers.push(
          setTimeout(() => {
            const first = out?.querySelector('.match, .rows');
            if (first) bigp?.aimAt(first);
          }, 1300),
        );
      }, heard + (quick ? 350 : 1500)),
    );
  }
</script>

<section class="bp-section ask" id="ask" aria-labelledby="ask-title">
  <div class="orb amber" aria-hidden="true"></div>
  <div class="wrap">
    <div class="bp-head" data-reveal>
      <h2 id="ask-title" data-split>Ask the way you would say it.</h2>
      <p class="lede">
        Pick a question. Most are the app's own examples. The answers on this page are scripted: there is no language
        model behind them.
      </p>
    </div>

    <div class="demo">
      <div class="host">
        <div class="say"><Bubble text={line} shown={said} tail="down" /></div>
        <div class="fig"><BigPFigure onready={(b) => (bigp = b)} /></div>
      </div>

      <div class="bz panel">
        <div class="bz-core">
          <div class="pick">
            {#each groups as g (g.name)}
              <div class="group">
                <h3>{g.name}</h3>
                <ul>
                  {#each g.asks as a (a.id)}
                    <li><button type="button" aria-pressed={active?.id === a.id} onclick={() => ask(a)}>{a.q}</button></li>
                  {/each}
                </ul>
              </div>
            {/each}
          </div>

          <div class="out" bind:this={out}>
            {#if phase === 'idle'}
              <p class="step">The answer appears here, drawn the way the Apple TV app shows it.</p>
            {:else if active}
              <!-- The question types itself in; a screen reader gets it once, from the button it pressed. -->
              <p class="asked" aria-hidden="true"><span>You asked:</span> {phase === 'listening' ? typed : active.q}</p>
              <div aria-live="polite">
              {#if phase === 'working'}
                <p class="step"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>{active.step}</p>
              {:else if phase === 'answer'}
                {#key active.id}
                  <div class="answer">
                    <p class="title">{active.line}</p>
                    {#if active.body}<p class="body">{active.body}</p>{/if}
                    {#if active.tag}<p class="meta"><span class="tag on">{active.tag}</span></p>{/if}
                    {#if active.matches}
                      <ul class="matches">
                        {#each active.matches as m, i (m.title)}
                          <BpMatch focused={i === 0} {...m} />
                        {/each}
                      </ul>
                    {/if}
                    {#if active.rows}<div class="card"><BpRows {...active.rows} /></div>{/if}
                  </div>
                {/key}
              {/if}
              </div>
            {/if}
          </div>
        </div>
      </div>
    </div>
    <p class="example">Scripted example. The films are real; the posters are drawn for this page and are not the films' artwork. TIDE is a demo title.</p>
    <div class="bp-next"><Cta note /></div>
  </div>
</section>

<style>
  .orb.amber { width: min(46rem, 100vw); aspect-ratio: 1; left: -18%; top: 20%; }
  .wrap { position: relative; }
  .demo { margin-top: 3rem; display: grid; gap: 1.5rem; align-items: end; }
  .host { position: relative; width: min(52vw, 13rem); margin-inline: auto; padding-top: 4.8rem; }
  .say { position: absolute; top: 0; left: 50%; width: max-content; max-width: min(84vw, 17rem); transform: translateX(-50%); }
  .bz-core { display: grid; gap: 1.6rem; }
  .pick { display: grid; gap: 1.3rem; align-content: start; }
  h3 { color: var(--muted); font-family: var(--font-sans); font-size: 0.86rem; font-weight: 600; letter-spacing: 0; }
  .group ul { margin-top: 0.55rem; display: flex; flex-wrap: wrap; gap: 0.45rem; }
  button { min-height: 44px; padding: 0.5rem 0.95rem; border-radius: 1.3rem; background: rgba(255, 255, 255, 0.05); box-shadow: inset 0 0 0 1px var(--hair); color: var(--muted); font-size: 0.92rem; line-height: 1.3; text-align: left; transition: background-color 0.4s var(--ease), color 0.4s var(--ease), transform 0.4s var(--ease); }
  button:hover { background: rgba(255, 255, 255, 0.1); color: var(--ink); }
  button:active { transform: scale(0.98); }
  button[aria-pressed='true'] { background: rgba(255, 176, 32, 0.14); box-shadow: inset 0 0 0 1px rgba(255, 176, 32, 0.4); color: var(--ink); }
  /* As tall as the tallest answer, so choosing another question never moves the page. */
  .out { min-height: 38rem; padding-top: 1.4rem; border-top: 1px solid var(--hair); scroll-margin-block: 5.5rem 1.5rem; }
  .asked { min-height: 2.9rem; color: var(--ink); font-size: 0.98rem; line-height: 1.45; }
  .asked span { color: var(--muted); }
  .step { display: flex; align-items: center; gap: 0.7rem; color: var(--muted); }
  .asked + div .step { margin-top: 0.8rem; }
  .dots { display: inline-flex; gap: 0.25rem; }
  .dots i { width: 0.36rem; height: 0.36rem; border-radius: 50%; background: var(--amber); animation: dot 1s var(--ease) infinite; }
  .dots i:nth-child(2) { animation-delay: 0.15s; }
  .dots i:nth-child(3) { animation-delay: 0.3s; }
  .answer { margin-top: 0.7rem; animation: rise 0.7s var(--ease) both; }
  .title { font-family: var(--display); font-size: clamp(1.6rem, 2.6vw, 2.1rem); font-weight: 700; letter-spacing: -0.02em; line-height: 1.12; text-wrap: balance; }
  .meta { margin-top: 0.8rem; }
  .body { margin-top: 0.7rem; max-width: 34rem; color: var(--muted); font-size: 1rem; line-height: 1.55; }
  .matches, .card { margin-top: 1.1rem; display: grid; grid-template-columns: minmax(0, 1fr); gap: 0.55rem; }
  .example { margin-top: 1.4rem; }
  @keyframes dot { 0%, 100% { opacity: 0.3; transform: translateY(0); } 40% { opacity: 1; transform: translateY(-3px); } }
  @keyframes rise { from { opacity: 0; transform: translateY(14px); } }
  /* A phone shows the two best matches; the third adds a screen of scrolling and no new idea. */
  @media (max-width: 559px) {
    .matches :global(.match:nth-child(n + 3)) { display: none; }
  }
  @media (max-width: 359px) {
    .out { min-height: 42rem; }
  }
  @media (min-width: 900px) {
    .demo { grid-template-columns: minmax(0, 13rem) minmax(0, 1fr); gap: 2rem; }
    .host { width: 100%; }
    .out { min-height: 36rem; }
    .example, .bp-next { margin-left: 15rem; }
  }
  /* Questions beside the answer only when the answer keeps room for a full title card. */
  @media (min-width: 1100px) {
    .bz-core { grid-template-columns: minmax(0, 17rem) minmax(0, 1fr); gap: 2rem; }
    .group ul { display: grid; }
    button { width: 100%; }
    .out { min-height: 31rem; padding-top: 0; padding-left: 2rem; border-top: 0; border-left: 1px solid var(--hair); }
  }
</style>
