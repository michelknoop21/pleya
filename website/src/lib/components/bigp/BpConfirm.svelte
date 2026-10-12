<script lang="ts">
  import { tick } from 'svelte';
  import LockIcon from '~icons/material-symbols-light/lock-outline';
  import BigPFigure from '$lib/bigp/BigP.svelte';
  import type { BigP } from '$lib/bigp/rig';
  import { onCue, type Cue } from './cue';

  let bigp: BigP | undefined;
  let card: HTMLElement;
  let outcome = $state<'open' | 'done' | 'cancelled'>('open');
  let entered = false;

  // The rig can arrive after the section scrolled in or the card was answered.
  function ready(b: BigP) {
    bigp = b;
    if (outcome !== 'open') return;
    b.aimAt(card);
    if (entered) b.set('attentive');
  }
  function cue({ name }: Cue) {
    if (name !== 'enter') return;
    entered = true;
    if (outcome === 'open') bigp?.set('attentive');
  }
  // The button that was pressed leaves the card: hand keyboard focus to what replaces it.
  const focus = (sel: string) => tick().then(() => card.querySelector<HTMLElement>(sel)?.focus());
  function decide(yes: boolean) {
    outcome = yes ? 'done' : 'cancelled';
    bigp?.aimAt(null);
    if (yes) {
      bigp?.react();
      bigp?.settle(2200);
    } else {
      bigp?.set('idle');
      bigp?.nod();
    }
    focus('.again');
  }
  function again() {
    outcome = 'open';
    bigp?.set('attentive');
    bigp?.aimAt(card);
    focus('.yes');
  }
</script>

<section class="bp-section confirm" id="confirm" aria-labelledby="confirm-title" use:onCue={cue}>
  <div class="orb red" aria-hidden="true"></div>
  <div class="wrap grid">
    <div class="copy" data-reveal>
      <p class="eyebrow">Who is in charge</p>
      <h2 id="confirm-title">Big P talks.<br /><span class="grad">Pleya decides.</span></h2>
      <p class="lede">
        Big P sends your question to a language model to understand what you mean. Pleya checks your rights, asks for
        confirmation on sensitive actions and carries them out itself.
      </p>
      <p class="aside">
        The model cannot press Confirm. Creating or removing a user, changing who may see a library, sending a request:
        each of them waits at a card like this one. A scan or a retry starts right away and shows its status.
      </p>
      <p class="aside">The password you type on that card in the app goes to your server. It does not go to Big P or to the AI provider.</p>
    </div>

    <div class="stage">
      <div class="fig"><BigPFigure onready={ready} /></div>
      <div class="bz card" bind:this={card}>
        <div class="bz-core">
          <p class="asked"><span>You asked:</span> Create Sam with access to Kids only</p>
          <div aria-live="polite">
            {#if outcome === 'open'}
              <p class="header">Pleya asks for confirmation</p>
              <h3>Create user</h3>
              <dl>
                <div><dt>User</dt><dd>Sam</dd></div>
                <div><dt>Server</dt><dd>Home server</dd></div>
                <div><dt>Access</dt><dd>Kids</dd></div>
                <div><dt>Admin</dt><dd>No</dd></div>
              </dl>
              <p class="field"><LockIcon aria-hidden="true" /><span>Password</span><span class="dots" aria-label="filled in, hidden">••••••••</span></p>
              <p class="note">This password does not go to Big P or to the AI provider.</p>
              <div class="buttons">
                <button type="button" class="no" onclick={() => decide(false)}>Cancel</button>
                <button type="button" class="yes" onclick={() => decide(true)}>Create</button>
              </div>
            {:else}
              <div class="result">
                <p class="header">{outcome === 'done' ? 'Carried out by Pleya' : 'Not carried out by Pleya'}</p>
                <h3>{outcome === 'done' ? 'User created' : 'Nothing was changed.'}</h3>
                <button type="button" class="no again" onclick={again}>Show the card again</button>
              </div>
            {/if}
          </div>
          <p class="example">Example card. Nothing on this page reaches a server.</p>
        </div>
      </div>
    </div>
  </div>
</section>

<style>
  .orb.red { width: min(56rem, 120vw); aspect-ratio: 1; left: -20%; top: 0; }
  .grid { position: relative; display: grid; gap: 3rem; }
  h2 { margin-top: 1.4rem; }
  .lede { margin-top: 1.6rem; }
  .aside { margin-top: 1rem; max-width: 34rem; color: var(--muted); }
  .stage { display: grid; grid-template-columns: minmax(0, 0.8fr) minmax(0, 1.2fr); align-items: end; gap: 0.5rem; }
  .fig { margin-left: -6%; }
  /* Fixed height: answering the card must not move the column next to it. */
  .card { position: relative; align-self: center; }
  .card .bz-core { min-height: 33rem; }
  .asked { color: var(--ink); font-size: 0.95rem; }
  .asked span { color: var(--faint); }
  .header { margin-top: 1.3rem; color: var(--amber); font-size: 0.72rem; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; }
  h3 { margin-top: 0.4rem; font-family: var(--display); font-size: clamp(1.5rem, 2.4vw, 2rem); letter-spacing: -0.02em; }
  dl { margin-top: 1rem; display: grid; }
  dl div { display: flex; justify-content: space-between; gap: 1rem; padding-block: 0.55rem; border-bottom: 1px solid var(--hair); font-size: 0.95rem; }
  dt { color: var(--muted); }
  .field { margin-top: 1rem; display: flex; align-items: center; gap: 0.6rem; padding: 0.75rem 0.9rem; border-radius: 0.8rem; background: rgba(255, 255, 255, 0.08); color: var(--muted); font-size: 0.95rem; }
  .field :global(svg) { font-size: 1.25rem; }
  .field .dots { margin-left: auto; color: var(--ink); letter-spacing: 0.15em; }
  .note { margin-top: 0.5rem; color: var(--muted); font-size: 0.8rem; }
  .buttons { margin-top: 1.2rem; display: flex; gap: 0.6rem; }
  button { flex: 1; min-height: 44px; padding: 0.6rem 1.1rem; border-radius: 999px; font-weight: 600; transition: transform 0.4s var(--ease), filter 0.4s var(--ease), background-color 0.4s var(--ease); }
  button:active { transform: scale(0.98); }
  .no { background: rgba(255, 255, 255, 0.08); }
  .no:hover { background: rgba(255, 255, 255, 0.14); }
  .yes { background: var(--brand); color: #120d0a; }
  .yes:hover { filter: brightness(1.08); }
  .result { display: grid; gap: 0.2rem; animation: rise 0.7s var(--ease) both; }
  .result button { margin-top: 1.2rem; justify-self: start; }
  .example { margin-top: 1.1rem; }
  @keyframes rise { from { opacity: 0; transform: translateY(12px); } }
  @media (max-width: 559px) {
    .stage { grid-template-columns: 1fr; }
    .fig { width: 11rem; margin: 0 0 -1.5rem; }
  }
  @media (min-width: 1024px) {
    .grid { grid-template-columns: minmax(0, 0.85fr) minmax(0, 1.15fr); gap: 4rem; align-items: center; }
  }
</style>
