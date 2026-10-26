<!--
  Een formulierveld zoals web.css het tekent: label van 13 px erboven, een vak
  van 44 px, en eronder hulptekst of een fout (`.field`, `.label`, `.help`).
  Designsysteem v2: het vak ligt dieper dan het paneel (--inset-bg) met een
  haarlijn, als een uitsparing; `mono` zet een pad of slug in de monoletter.

  Zonder children tekent Field zelf een tekstinvoer. Met children levert het
  alleen de bedrading: de snippet krijgt het id, de aria-describedby en de
  foutstaat mee en legt die op zijn eigen element. Zo gebruiken Select en
  ConfirmDialog hetzelfde label- en foutpad zonder een tweede kopie ervan.

  Een wachtwoordveld krijgt rechts in het vak de oog-knop uit beeld 12 en 40.
  Het label blijft "Wachtwoord tonen"; `aria-pressed` zegt of het zichtbaar is,
  zodat een schermlezer niet bij elke druk een andere knop hoort.
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
  import { t } from '../i18n';

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
    /** Monoletter, voor paden, slugs en sleutels die iemand letterlijk overtypt. */
    mono?: boolean;
    /** Hoogstens zoveel tekens; de browser stopt het typen. */
    maxlength?: number;
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
    maxlength,
    disabled = false,
    required = false,
    hideLabel = false,
    mono = false,
    oninput,
    children
  }: Props = $props();

  const uid = $props.id();
  const controlId = $derived(id ?? `${uid}-control`);
  const hintId = $derived(`${controlId}-hint`);
  const errorId = $derived(`${controlId}-error`);
  const invalid = $derived(Boolean(error));
  let revealed = $state(false);
  const inputType = $derived(type === 'password' && revealed ? 'text' : type);

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

<div class="fld" class:fld--err={invalid} class:fld--dis={disabled} class:fld--mono={mono}>
  <label class="fld__label" class:visually-hidden={hideLabel} for={controlId}>{label}</label>

  <div class="fld__control" class:fld__control--reveal={type === 'password' && !children}>
    {#if children}
      {@render children(control)}
    {:else}
      <input
        id={controlId}
        type={inputType}
        {placeholder}
        {autocomplete}
        {maxlength}
        {disabled}
        {required}
        aria-invalid={invalid ? 'true' : undefined}
        aria-describedby={describedby}
        bind:value
        oninput={(event) => oninput?.(event.currentTarget.value)}
      />
      {#if type === 'password'}
        <button
          type="button"
          class="fld__reveal"
          aria-label={t('field.showPassword')}
          aria-pressed={revealed}
          aria-controls={controlId}
          {disabled}
          onclick={() => (revealed = !revealed)}
        >
          <!-- Het oog uit build.mjs; doorgestreept zolang het wachtwoord zichtbaar is. -->
          <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
            <g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
              <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z" />
              <circle cx="12" cy="12" r="3" />
              {#if revealed}<path d="M4 4l16 16" />{/if}
            </g>
          </svg>
        </button>
      {/if}
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
    margin-bottom: 7px;
    font-size: 13px;
    font-weight: 500;
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
    border: 1px solid var(--hairline);
    background: var(--inset-bg);
    color: var(--ink);
    font: inherit;
    font-size: 15px;
    transition:
      border-color var(--dur-fast) var(--ease),
      box-shadow var(--dur-fast) var(--ease);
  }

  /* Dezelfde :not-keten als de vakstijl, anders wint die de lettermaat. */
  .fld--mono .fld__control :global(input:not([type='checkbox']):not([type='radio'])) {
    font-family: var(--font-mono);
    font-size: var(--text-mono-size);
  }

  .fld__control :global(textarea) {
    padding-block: 11px;
  }

  .fld__control :global(::placeholder) {
    color: var(--ink-3);
  }

  /*
   * Een tekstvak toont focus als een rand van 1 px in inkt, zonder ring
   * (mockup 23, 40 en 42). Browsers zetten :focus-visible bij een tekstvak ook
   * na een muisklik, dus de ring van base.css zou hier elk formulier zwaar
   * maken. Knoppen, chips, keuzes en schakelaars houden die ring wel.
   */
  .fld__control :global(:is(input:not([type='checkbox']):not([type='radio']), select, textarea):focus) {
    border-color: var(--ink);
    outline: none;
  }

  /*
   * Dezelfde :not-keten als de vakstijl, anders wint die op specificiteit en
   * blijft de rand van een fout of focus doorzichtig.
   */
  .fld--err .fld__control :global(:is(input:not([type='checkbox']):not([type='radio']), select, textarea)) {
    border-color: var(--danger-ink);
  }

  /*
   * Een foutveld met focus houdt zijn rode rand en wordt 2 px dik, anders is er
   * op juist het veld dat aandacht vraagt geen focusverschil. De tweede pixel is
   * een schaduw, zodat het vak niet verschuift. De northstar tekent deze staat
   * niet; .field.err in web.css kent alleen de rode rand.
   */
  .fld--err .fld__control :global(:is(input:not([type='checkbox']):not([type='radio']), select, textarea):focus) {
    box-shadow: 0 0 0 1px var(--danger-ink);
  }

  .fld__control :global(:is(input, select, textarea):disabled) {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .fld__control--reveal {
    position: relative;
  }

  /* Ruimte voor de oog-knop, zodat lange invoer er niet onder verdwijnt. */
  .fld__control--reveal :global(input:not([type='checkbox']):not([type='radio'])) {
    padding-right: 48px;
  }

  .fld__reveal {
    position: absolute;
    top: 0;
    right: 0;
    display: grid;
    place-items: center;
    width: var(--touch-target);
    height: var(--touch-target);
    border: 0;
    border-radius: var(--radius-md);
    background: none;
    color: var(--ink-2);
    cursor: pointer;
  }

  .fld__reveal[aria-pressed='true'] {
    color: var(--ink);
  }

  .fld__help {
    margin-top: 7px;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  .fld__help--err {
    color: var(--danger-ink);
  }
</style>
