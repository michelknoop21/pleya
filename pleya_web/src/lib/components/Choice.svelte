<!--
  Een radiogroep als kaarten (`.choice` in web.css). Twee vormen uit de
  northstar: onder elkaar met een rondje links (22, soort van een bibliotheek)
  en naast elkaar als tegels met een icoon (42, setup stap 3).

  Onder elke kaart zit een native radio. De browser levert dan de pijltjes
  binnen de groep, één tabstop voor de hele groep en de rol voor een
  schermlezer; de kaart is alleen de tekening eromheen. De radio is visueel
  verborgen, dus de focusring staat op de kaart via :has(:focus-visible).
  De naam van een radio is alleen de titel (aria-labelledby): het omhullende
  label plakt anders de omschrijving eraan vast, en die hoort in
  aria-describedby. De fieldset draagt role="radiogroup", want alleen die rol
  kent aria-invalid; een kale fieldset (rol group) niet.
-->
<script lang="ts" module>
  export interface ChoiceOption {
    value: string;
    label: string;
    description?: string;
    disabled?: boolean;
  }
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    legend: string;
    options: ChoiceOption[];
    value?: string;
    name?: string;
    layout?: 'list' | 'grid';
    hint?: string;
    error?: string;
    disabled?: boolean;
    required?: boolean;
    /** Icoon per optie; alleen getekend in de tegelvorm. */
    icon?: Snippet<[ChoiceOption]>;
    onchange?: (value: string) => void;
  }

  let {
    legend,
    options,
    value = $bindable(''),
    name,
    layout = 'list',
    hint,
    error,
    disabled = false,
    required = false,
    icon,
    onchange
  }: Props = $props();

  const uid = $props.id();
  const groupName = $derived(name ?? `${uid}-choice`);
  const hintId = `${uid}-hint`;
  const errorId = `${uid}-error`;
  const describedby = $derived(
    [error ? errorId : null, hint ? hintId : null].filter(Boolean).join(' ') || undefined
  );
</script>

<fieldset
  class="cho"
  class:cho--grid={layout === 'grid'}
  class:cho--err={Boolean(error)}
  role="radiogroup"
  aria-describedby={describedby}
  aria-invalid={error ? 'true' : undefined}
  {disabled}
>
  <legend class="cho__legend">{legend}</legend>

  <div class="cho__options">
    {#each options as option, i (option.value)}
      {@const descId = `${uid}-opt${i}-desc`}
      {@const titleId = `${uid}-opt${i}-title`}
      <label
        class="cho__card"
        class:cho__card--on={option.value === value}
        class:cho__card--dis={disabled || option.disabled}
      >
        <input
          class="visually-hidden"
          type="radio"
          name={groupName}
          value={option.value}
          disabled={option.disabled}
          {required}
          aria-labelledby={titleId}
          aria-describedby={option.description ? descId : undefined}
          bind:group={value}
          onchange={() => onchange?.(option.value)}
        />
        {#if layout === 'grid' && icon}
          <span class="cho__icon" aria-hidden="true">{@render icon(option)}</span>
        {:else if layout === 'list'}
          <span class="cho__radio" aria-hidden="true"></span>
        {/if}
        <span class="cho__body">
          <span class="cho__title" id={titleId}>{option.label}</span>
          {#if option.description}
            <span class="cho__sub" id={descId}>{option.description}</span>
          {/if}
        </span>
      </label>
    {/each}
  </div>

  {#if error}
    <p class="cho__help cho__help--err" id={errorId}>{error}</p>
  {/if}
  {#if hint}
    <p class="cho__help" id={hintId}>{hint}</p>
  {/if}
</fieldset>

<style>
  .cho {
    border: 0;
    padding: 0;
    margin: 0;
    min-width: 0;
  }

  .cho__legend {
    padding: 0;
    margin-bottom: 6px;
    font-size: 13px;
    color: var(--ink-2);
  }

  .cho__options {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .cho--grid .cho__options {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 10px;
  }

  .cho__card {
    display: flex;
    align-items: center;
    gap: 14px;
    min-height: var(--touch-target);
    padding: 14px 16px;
    border-radius: var(--radius-md);
    border: 1px solid transparent;
    background: var(--surface);
    cursor: pointer;
    transition: border-color var(--dur-fast) var(--ease);
  }

  .cho--grid .cho__card {
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    padding: 16px;
  }

  .cho__card--on {
    border-color: var(--ink);
  }

  .cho--err .cho__card {
    border-color: var(--accent);
  }

  .cho--err .cho__card--on {
    border-color: var(--ink);
  }

  .cho__card:has(input:focus-visible) {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }

  .cho__card--dis {
    opacity: 0.5;
    cursor: not-allowed;
  }

  @media (hover: hover) {
    .cho__card:not(.cho__card--dis):not(.cho__card--on):hover {
      border-color: var(--ink-4);
    }
  }

  .cho__radio {
    flex: none;
    width: 20px;
    height: 20px;
    border-radius: var(--radius-pill);
    border: 2px solid var(--ink-3);
  }

  .cho__card--on .cho__radio {
    border-color: var(--ink);
    background: radial-gradient(circle, var(--ink) 0 5px, transparent 6px);
  }

  .cho__icon {
    display: inline-flex;
    width: 22px;
    height: 22px;
    color: var(--ink);
  }

  .cho__body {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }

  .cho__title {
    font-size: 15px;
    font-weight: 500;
    color: var(--ink);
  }

  .cho__sub {
    margin-top: 2px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .cho__help {
    margin-top: 6px;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  .cho__help--err {
    color: var(--danger-ink);
  }
</style>
