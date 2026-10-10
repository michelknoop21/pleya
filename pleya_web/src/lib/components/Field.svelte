<!--
  Een formulierveld zoals web.css het tekent: label van 13 px erboven, een vak
  van 44 px op het oppervlak, en eronder hulptekst of een fout (`.field`,
  `.label`, `.help`).

  Zonder children tekent Field zelf een tekstinvoer. Met children levert het
  alleen de bedrading: de snippet krijgt het id, de aria-describedby en de
  foutstaat mee en legt die op zijn eigen element. Zo gebruiken Select en
  ConfirmDialog hetzelfde label- en foutpad zonder een tweede kopie ervan.
-->
<script lang="ts" module>
  /** Wat een eigen besturingselement nodig heeft om aan het label te hangen. */
  export interface FieldControl {
    id: string;
    describedby: string | undefined;
    invalid: boolean;
    disabled: boolean;
    required: boolean;
  }
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLInputAttributes } from 'svelte/elements';

  interface Props {
    label: string;
    value?: string;
    id?: string;
    hint?: string;
    error?: string;
    type?: 'text' | 'password' | 'email' | 'search' | 'url' | 'number';
    placeholder?: string;
    autocomplete?: HTMLInputAttributes['autocomplete'];
    disabled?: boolean;
    required?: boolean;
    /** Label alleen voor een schermlezer, waar de context het al zegt. */
    hideLabel?: boolean;
    oninput?: (value: string) => void;
    children?: Snippet<[FieldControl]>;
  }

  let {
    label,
    value = $bindable(''),
    id,
    hint,
    error,
    type = 'text',
    placeholder,
    autocomplete,
    disabled = false,
    required = false,
    hideLabel = false,
    oninput,
    children
  }: Props = $props();

  const uid = $props.id();
  const controlId = $derived(id ?? `${uid}-control`);
  const hintId = $derived(`${controlId}-hint`);
  const errorId = $derived(`${controlId}-error`);
  const invalid = $derived(Boolean(error));

  // De fout staat vóór de hint in de beschrijving: die is wat er nu toe doet.
  const describedby = $derived(
    [error ? errorId : null, hint ? hintId : null].filter(Boolean).join(' ') || undefined
  );

  const control: FieldControl = $derived({
    id: controlId,
    describedby,
    invalid,
    disabled,
    required
  });
</script>

<div class="fld" class:fld--err={invalid} class:fld--dis={disabled}>
  <label class="fld__label" class:visually-hidden={hideLabel} for={controlId}>{label}</label>

  <div class="fld__control">
    {#if children}
      {@render children(control)}
    {:else}
      <input
        id={controlId}
        {type}
        {placeholder}
        {autocomplete}
        {disabled}
        {required}
        aria-invalid={invalid ? 'true' : undefined}
        aria-describedby={describedby}
        bind:value
        oninput={(event) => oninput?.(event.currentTarget.value)}
      />
    {/if}
  </div>

  {#if error}
    <p class="fld__help fld__help--err" id={errorId}>{error}</p>
  {/if}
  {#if hint}
    <p class="fld__help" id={hintId}>{hint}</p>
  {/if}
</div>

<style>
  .fld {
    display: flex;
    flex-direction: column;
  }

  .fld__label {
    display: block;
    margin-bottom: 6px;
    font-size: 13px;
    color: var(--ink-2);
  }

  /*
   * De vakstijl geldt ook voor wat een snippet levert; dat element valt buiten
   * de scope van dit bestand, vandaar :global binnen de eigen wrapper.
   */
  .fld__control :global(input:not([type='checkbox']):not([type='radio'])),
  .fld__control :global(select),
  .fld__control :global(textarea) {
    width: 100%;
    min-height: var(--touch-target);
    padding: 0 14px;
    border-radius: var(--radius-md);
    border: 1px solid transparent;
    background: var(--surface);
    color: var(--ink);
    font: inherit;
    font-size: 15px;
    transition: border-color var(--dur-fast) var(--ease);
  }

  .fld__control :global(textarea) {
    padding-block: 11px;
  }

  .fld__control :global(::placeholder) {
    color: var(--ink-3);
  }

  .fld__control :global(:is(input, select, textarea):focus) {
    border-color: var(--ink);
  }

  .fld__control :global(:is(input, select, textarea):focus-visible) {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }

  .fld--err .fld__control :global(:is(input, select, textarea)) {
    border-color: var(--accent);
  }

  .fld__control :global(:is(input, select, textarea):disabled) {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .fld__help {
    margin-top: 6px;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  .fld__help--err {
    color: var(--danger-ink);
  }
</style>
