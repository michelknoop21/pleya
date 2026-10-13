<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import MicIcon from '~icons/material-symbols-light/mic-outline-rounded';
  import TurnIcon from '~icons/material-symbols-light/subdirectory-arrow-right-rounded';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import { prefersReducedMotion } from '$lib/bigp/loop';
  import type { BigP } from '$lib/bigp/rig';
  import { say } from '$lib/bigp/say';
  import { asks, followUps, indexOf, starters, type Ask } from './asks';
  import BpMatch from './BpMatch.svelte';
  import BpRows from './BpRows.svelte';
  import Cta from './Cta.svelte';

  // Big P as the app shows him when you call him: his balloon holds the greeting with three
  // questions, then your question and his answer; next to him float the follow-ups, and under
  // it all sits the bar you ask from. Here every question runs a fixed script.
  const greeting = 'Hi, what are we looking for?';

  type Phase = 'idle' | 'listening' | 'working' | 'answer';
  let bigp: BigP | undefined;
  let phase = $state<Phase>('idle');
  let active = $state<Ask | null>(null);
  let typed = $state('');
  let said = $state('');
  let timers: ReturnType<typeof setTimeout>[] = [];
  let stopTalking = () => {};
  // Counts the questions asked, so work a pose is still loading for can tell it has been overtaken.
  let run = 0;
  let sheet = $state<HTMLElement>();
  let stage = $state<HTMLElement>();

  const next = $derived(phase === 'answer' && active ? followUps(active) : []);

  function clear() {
    run++;
    timers.forEach(clearTimeout);
    timers = [];
    stopTalking();
    bigp?.aimAt(null);
    bigp?.relax();
  }
  onDestroy(clear);

  const wide = () => matchMedia('(min-width: 900px)').matches;
  // The balloon may sit above the window after a tap on a follow-up: bring it back in.
  function reveal() {
    if (!sheet || !stage) return;
    // Only while the demo is still on screen: a visitor who scrolled on is not pulled back.
    const seen = stage.getBoundingClientRect();
    if (seen.bottom < 0 || seen.top > window.innerHeight) return;
    // A balloon taller than the window has no nearest edge: when its top is cut off, go to the top.
    const cut = sheet.getBoundingClientRect().top < 80;
    sheet.scrollIntoView({ block: cut ? 'start' : 'nearest', behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  }

  // A pressed chip leaves the page with the state it belonged to: hand keyboard focus on. It
  // goes to the reply, so the next Tab reaches New and the follow-ups before the bar.
  const focus = (sel: string) => tick().then(() => stage?.querySelector<HTMLElement>(sel)?.focus({ preventScroll: true }));

  function reset() {
    clear();
    phase = 'idle';
    active = null;
    typed = '';
    bigp?.set('idle');
    focus('.starters .chip');
  }

  // Listening, working, answering: the three beats of the app.
  function ask(a: Ask) {
    clear();
    const quick = prefersReducedMotion();
    active = a;
    phase = 'listening';
    said = '';
    bigp?.set('listening');
    tick().then(reveal);
    if (stage?.contains(document.activeElement) && !document.activeElement?.classList.contains('bar')) focus('.reply');
    const per = quick ? 0 : Math.min(26, 1100 / a.q.length);
    typed = quick ? a.q : '';
    for (let i = 1; i <= a.q.length && !quick; i++) timers.push(setTimeout(() => (typed = a.q.slice(0, i)), i * per));
    const heard = a.q.length * per + (quick ? 250 : 450);
    timers.push(
      setTimeout(() => {
        phase = 'working';
        typed = '';
        bigp?.set('working');
        bigp?.nod(0.7);
      }, heard),
      setTimeout(() => {
        phase = 'answer';
        // The balloon is at its tallest now: make sure the question and the answer line are in view.
        tick().then(reveal);
        if (!bigp) return void (said = a.line);
        const b = bigp;
        const mine = run;
        b.set('success');
        b.hop(70, 0.55);
        stopTalking = say(b, a.line, (t) => (said = t), () => b.settle(1400));
        timers.push(
          setTimeout(() => {
            // Beside the balloon he points at the first card; under it he presents with an open hand.
            const first = sheet?.querySelector('.match, .rows');
            if (wide() && first) b.aimAt(first);
            else b.ensure('vinger_presenteren').then(() => mine === run && b.gesture('vinger_presenteren', 2600), () => {});
          }, 1300),
        );
      }, heard + (quick ? 350 : 1500)),
    );
  }
  // The bar asks the next question in the list, so the demo can be walked through with one button.
  const askNext = () => ask(asks[(active ? indexOf(active) + 1 : 0) % asks.length]);
</script>

<section class="bp-section ask" id="ask" aria-labelledby="ask-title">
  <div class="orb amber" aria-hidden="true"></div>
  <div class="wrap">
    <div class="bp-head" data-reveal>
      <h2 id="ask-title" data-split>Ask the way you would say it.</h2>
      <p class="lede">Pick a question and watch him answer. This is a scripted example: there is no language model behind this page.</p>
    </div>

    <div class="stage" bind:this={stage}>
      <div class="sheet" bind:this={sheet}>
        {#if phase === 'idle'}
          <p class="hello">{greeting}</p>
          <ul class="starters">
            {#each starters as a (a.id)}
              <li><button type="button" class="chip" onclick={() => ask(a)}>{a.q}</button></li>
            {/each}
          </ul>
        {/if}
        <div class="reply" aria-live="polite" tabindex="-1">
          {#if active && phase === 'listening'}
            <p class="status"><i aria-hidden="true"></i>Listening…</p>
            <p class="hello">Say your question, or type it.</p>
          {:else if active}
            <div class="top">
              <p class="asked"><span>You asked:</span> {active.q}</p>
              {#if phase === 'answer'}<button type="button" class="new" onclick={reset}>New</button>{/if}
            </div>
            {#if phase === 'working'}
              <p class="hello">Let me check…</p>
              <p class="step"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>{active.step}</p>
            {:else}
              {#key active.id}
                <div class="answer">
                  <p class="hello"><span class="sr">{active.line}</span><span aria-hidden="true">{said}</span></p>
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
          {/if}
        </div>
      </div>

      <div class="fu">
        {#if next.length}
          <ul aria-label="Ask next">
            {#each next as a (a.id)}
              <li><button type="button" class="chip" onclick={() => ask(a)}><TurnIcon aria-hidden="true" />{a.q}</button></li>
            {/each}
          </ul>
        {/if}
      </div>

      <div class="fig"><BigPFigure onready={(b) => (bigp = b)} /></div>

      <button type="button" class="bar" class:busy={phase === 'listening'} onclick={askNext}>
        <span class:placeholder={!typed}>{typed || (phase === 'idle' ? 'Ask Big P' : 'Ask more')}<span class="sr">, the next example question</span></span>
        <span class="mic" aria-hidden="true"><MicIcon /></span>
      </button>
    </div>

    <p class="example">Scripted example. The films are real; the posters are drawn for this page and are not the films' artwork. TIDE is a demo title.</p>
    <div class="bp-next"><Cta note /></div>
  </div>
</section>

<style>
  .ask { --panel: rgba(31, 35, 35, 0.97); --line: rgba(255, 255, 255, 0.14); --pill: rgba(255, 255, 255, 0.12); }
  .orb.amber { width: min(46rem, 100vw); aspect-ratio: 1; left: -18%; top: 20%; }
  .wrap { position: relative; }

  /* The app surface: balloon, then Big P with the follow-ups beside him, then the ask bar. */
  .stage { margin-top: 2.5rem; display: grid; grid-template-columns: minmax(0, 1fr) 42%; grid-template-areas: 'sheet sheet' 'fu fig' 'bar bar'; grid-template-rows: minmax(25rem, auto) auto auto; gap: 0.9rem 0.5rem; align-items: end; }
  /* The balloon hugs what it says and grows upward from its tail, into room the stage keeps free. */
  .sheet { grid-area: sheet; position: relative; padding: 1.1rem; border-radius: 1.75rem; background: var(--panel); box-shadow: inset 0 0 0 1px var(--line), 0 24px 60px -30px #000; scroll-margin-block: 5.5rem 1.5rem; }
  .sheet::after { content: ''; position: absolute; right: 19%; bottom: -0.55rem; width: 1.2rem; height: 1.2rem; background: var(--panel); border-right: 1px solid var(--line); border-bottom: 1px solid var(--line); border-radius: 0 0 4px 0; transform: rotate(45deg); }
  .fu { grid-area: fu; align-self: center; min-height: 13.5rem; display: grid; align-content: center; }
  .fu ul { display: flex; flex-direction: column; align-items: flex-start; gap: 0.5rem; }
  .fig { grid-area: fig; }

  .hello { font-family: var(--display); font-size: clamp(1.45rem, 2.6vw, 2rem); font-weight: 700; letter-spacing: -0.02em; line-height: 1.15; text-wrap: balance; }
  .starters { margin-top: 0.9rem; display: grid; justify-items: start; gap: 0.55rem; }
  .chip { display: inline-flex; align-items: center; gap: 0.45rem; min-height: 44px; padding: 0.55rem 1rem; border-radius: 1.4rem; background: var(--pill); color: var(--ink); font-size: 0.98rem; line-height: 1.3; text-align: left; transition: background-color 0.4s var(--ease), transform 0.4s var(--ease); }
  .chip:hover { background: rgba(255, 255, 255, 0.2); }
  .chip:active { transform: scale(0.98); }
  .fu .chip { padding-left: 0.7rem; background: #2a2e2e; box-shadow: inset 0 0 0 1px var(--line), 0 10px 22px -12px #000; font-size: 0.9rem; animation: rise 0.6s var(--ease) both; }
  .fu li:nth-child(2) .chip { animation-delay: 0.08s; }
  .fu li:nth-child(3) .chip { animation-delay: 0.16s; }
  .fu .chip :global(svg) { flex: none; font-size: 1.2rem; color: rgba(255, 255, 255, 0.65); }
  .new { flex: none; min-height: 44px; padding: 0.4rem 1rem; border-radius: 999px; background: var(--pill); color: var(--muted); font-size: 0.9rem; transition: background-color 0.4s var(--ease); }
  .new:hover { background: rgba(255, 255, 255, 0.2); color: var(--ink); }

  /* Focus only lands here from script, as the place to tab on from. */
  .reply:focus { outline: none; }
  .status { display: flex; align-items: center; gap: 0.55rem; margin-bottom: 0.5rem; color: var(--muted); }
  .status i { width: 0.6rem; height: 0.6rem; border-radius: 50%; background: #3dd68c; }
  .top { display: flex; align-items: flex-start; gap: 0.5rem; margin-bottom: 0.9rem; }
  .asked { flex: 1; min-width: 0; padding: 0.6rem 0.8rem; border-radius: 0.8rem; background: var(--pill); font-size: 0.95rem; line-height: 1.35; }
  .asked span { color: rgba(255, 255, 255, 0.65); }
  .step { margin-top: 0.8rem; display: flex; align-items: center; gap: 0.7rem; color: var(--muted); }
  .dots { display: inline-flex; gap: 0.25rem; }
  .dots i { width: 0.36rem; height: 0.36rem; border-radius: 50%; background: var(--amber); animation: dot 1s var(--ease) infinite; }
  .dots i:nth-child(2) { animation-delay: 0.15s; }
  .dots i:nth-child(3) { animation-delay: 0.3s; }
  .answer { animation: rise 0.6s var(--ease) both; }
  .answer .hello { min-height: 1.15em; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  .meta { margin-top: 0.8rem; }
  .body { margin-top: 0.6rem; max-width: 34rem; color: var(--muted); line-height: 1.5; }
  .matches, .card { margin-top: 0.9rem; display: grid; grid-template-columns: minmax(0, 1fr); gap: 0.55rem; }

  /* The bar you ask from. Here it is a button: it asks the next example. */
  .bar { grid-area: bar; display: flex; align-items: center; justify-content: space-between; gap: 0.8rem; min-height: 3.5rem; padding: 0.45rem 0.45rem 0.45rem 1.25rem; border-radius: 999px; background: #1b1d1f; box-shadow: inset 0 0 0 1px var(--line); color: var(--ink); font-size: 1.02rem; line-height: 1.3; text-align: left; transition: box-shadow 0.5s var(--ease), background-color 0.4s var(--ease); }
  .bar:hover { background: #232628; }
  .bar.busy { box-shadow: inset 0 0 0 1px rgba(61, 214, 140, 0.7); }
  .placeholder { color: rgba(255, 255, 255, 0.5); }
  .mic { flex: none; display: grid; place-items: center; width: 2.6rem; height: 2.6rem; border-radius: 50%; background: rgba(255, 255, 255, 0.12); font-size: 1.4rem; }
  .example { margin-top: 1.4rem; }

  @keyframes dot { 0%, 100% { opacity: 0.3; transform: translateY(0); } 40% { opacity: 1; transform: translateY(-3px); } }
  @keyframes rise { from { opacity: 0; transform: translateY(12px); } }

  /* A phone shows the two best matches; the third adds a screen of scrolling and no new idea. */
  @media (max-width: 559px) {
    .matches :global(.match:nth-child(n + 3)) { display: none; }
  }
  @media (min-width: 560px) {
    .stage { grid-template-columns: minmax(0, 1fr) 14rem; }
    .sheet { padding: 1.5rem; }
  }
  /* Wide: Big P stands beside his balloon, as on a tablet or the television. */
  @media (min-width: 900px) {
    .stage { grid-template-columns: 17rem minmax(0, 1fr); grid-template-areas: 'fig sheet' 'fig fu' 'bar bar'; grid-template-rows: minmax(31rem, auto) auto auto; gap: 1rem 1.5rem; }
    .sheet { padding: 1.75rem; }
    .sheet::after { right: auto; left: -0.6rem; bottom: 4.5rem; border-right: 0; border-left: 1px solid var(--line); border-radius: 0 0 0 4px; }
    .fu { min-height: 6.6rem; align-self: start; align-content: start; }
    .fu ul { flex-direction: row; flex-wrap: wrap; align-items: center; }
    .fig { align-self: end; }
    .bar { margin-left: 18.5rem; }
    .example, .bp-next { margin-left: 18.5rem; }
  }
</style>
