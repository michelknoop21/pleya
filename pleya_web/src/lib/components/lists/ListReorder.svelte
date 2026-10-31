<!--
  Herordenen als eigen modus (18). De rijen staan los van de gewone weergave: er
  is geen link en geen menu, en niets gaat naar de server tot "Volgorde bewaren".

  Elke rij heeft een greep. Op de greep verplaatsen de pijltjes omhoog en omlaag
  de rij, Home en End naar de randen, en de focus blijft op dezelfde rij staan;
  een live-regio zegt waar hij nu staat. Twee knoppen per rij doen hetzelfde op
  een aanraakscherm. Slepen met de muis komt daar als gemak bovenop en is nooit
  de enige weg.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import Alert from '../Alert.svelte';
  import type { Item } from '../../api/types';
  import { describeError } from '../../api/errors';
  import { t } from '../../i18n';

  interface Props {
    items: Item[];
    /** Een volgorde om mee te beginnen, als die van `items` afwijkt. */
    kept?: Item[] | null;
    onsave: (order: string[]) => Promise<void>;
    oncancel: () => void;
  }

  let { items, kept = null, onsave, oncancel }: Props = $props();

  // svelte-ignore state_referenced_locally
  let order = $state((kept ?? items).slice());
  let announcement = $state('');
  let saving = $state(false);
  let error = $state<string | null>(null);
  let dragging = $state<string | null>(null);
  let list = $state<HTMLOListElement>();

  const changed = $derived(order.some((item, index) => item.id !== items[index]?.id));

  async function move(from: number, to: number, focusSelector = '.handle'): Promise<void> {
    if (to < 0 || to >= order.length || to === from) return;
    const next = order.slice();
    const [item] = next.splice(from, 1);
    if (!item) return;
    next.splice(to, 0, item);
    order = next;
    announcement = t('lists.moved', { title: item.title, position: to + 1, count: next.length });
    await tick();
    list?.querySelector<HTMLElement>(`[data-item-id="${item.id}"] ${focusSelector}`)?.focus();
  }

  function keydown(event: KeyboardEvent, index: number): void {
    const target = { ArrowUp: index - 1, ArrowDown: index + 1, Home: 0, End: order.length - 1 }[event.key];
    if (target === undefined) return;
    event.preventDefault();
    void move(index, target);
  }

  function dragover(event: DragEvent, index: number): void {
    if (!dragging) return;
    event.preventDefault();
    const from = order.findIndex((item) => item.id === dragging);
    if (from >= 0 && from !== index) void move(from, index);
  }

  async function save(): Promise<void> {
    if (saving) return;
    saving = true;
    error = null;
    try {
      await onsave(order.map((item) => item.id));
    } catch (err) {
      error = describeError(err);
      saving = false;
    }
  }
</script>

<p class="help" id="reorder-help">{t('lists.reorderHelp')}</p>
{#if error}<Alert tone="err">{error}</Alert>{/if}

<ol class="rows" bind:this={list} aria-describedby="reorder-help">
  {#each order as item, index (item.id)}
    <li
      class="row"
      class:row--dragging={dragging === item.id}
      data-item-id={item.id}
      draggable="true"
      ondragstart={(event) => { dragging = item.id; event.dataTransfer?.setData('text/plain', item.id); }}
      ondragover={(event) => dragover(event, index)}
      ondragend={() => (dragging = null)}
      ondrop={(event) => { event.preventDefault(); dragging = null; }}
    >
      <button
        type="button"
        class="handle"
        aria-label={t('lists.moveHandle', { title: item.title, position: index + 1, count: order.length })}
        aria-describedby="reorder-help"
        onkeydown={(event) => keydown(event, index)}
      >
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 8h14M5 12h14M5 16h14" /></svg>
      </button>
      <span class="row__n">{index + 1}</span>
      <span class="row__title">{item.title}</span>
      <span class="row__moves">
        <button type="button" class="step" disabled={index === 0} aria-label={t('lists.moveUp', { title: item.title })} onclick={() => void move(index, index - 1, '.step')}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 15 6-6 6 6" /></svg>
        </button>
        <button type="button" class="step" disabled={index === order.length - 1} aria-label={t('lists.moveDown', { title: item.title })} onclick={() => void move(index, index + 1, '.step:not(:disabled)')}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6" /></svg>
        </button>
      </span>
    </li>
  {/each}
</ol>

<div class="visually-hidden" role="status" aria-live="polite">{announcement}</div>

<div class="actions">
  <button type="button" class="btn" disabled={!changed || saving} onclick={() => void save()}>{t('lists.saveOrder')}</button>
  <button type="button" class="btn btn--secondary" disabled={saving} onclick={oncancel}>{t('lists.cancel')}</button>
</div>

<style>
  .help {
    margin: 0 0 12px;
    font-size: 14px;
    color: var(--ink-2);
  }

  .rows {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    list-style: none;
    overflow: hidden;
    border-radius: var(--radius-card);
    background: var(--panel);
  }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 56px;
    padding: 6px 8px;
  }

  .row + .row {
    box-shadow: inset 0 1px 0 var(--hairline);
  }

  .row--dragging {
    background: var(--elevated);
  }

  .handle,
  .step {
    display: inline-flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--ink-2);
    cursor: grab;
  }

  .step {
    cursor: pointer;
  }

  .step:disabled {
    opacity: 0.3;
    cursor: default;
  }

  .handle:focus-visible,
  .step:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: -2px;
  }

  .row__n {
    flex: none;
    width: 28px;
    text-align: center;
    font-size: 14px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .row__title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 15px;
    color: var(--ink);
  }

  .row__moves {
    display: flex;
    flex: none;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 16px;
  }

  @media (max-width: 479px) {
    .row__n {
      display: none;
    }

    .row {
      gap: 0;
      padding: 6px 4px;
    }
  }
</style>
