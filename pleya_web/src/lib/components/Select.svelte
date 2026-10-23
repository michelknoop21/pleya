<!--
  Een keuzelijst in de vorm van een veld (`.field.select` in web.css): het vak
  van Field met een chevron rechts. Onder de huid zit een native select, want
  de browser levert dan het toetsenbordgedrag en de schermlezerrol, en op een
  telefoon het eigen keuzewiel.
-->
<script lang="ts" module>
  export interface SelectOption {
    value: string;
    label: string;
    disabled?: boolean;
  }
</script>

<script lang="ts">
  import Field from './Field.svelte';

  interface Props {
    label: string;
    options: SelectOption[];
    value?: string;
    id?: string;
    hint?: string;
    error?: string;
    /** Een lege eerste regel, voor een keuze die nog niet gemaakt is. */
    placeholder?: string;
    disabled?: boolean;
    required?: boolean;
    hideLabel?: boolean;
    onchange?: (value: string) => void;
  }

  let {
    label,
    options,
    value = $bindable(''),
    id,
    hint,
    error,
    placeholder,
    disabled = false,
    required = false,
    hideLabel = false,
    onchange
  }: Props = $props();
</script>

<Field {label} {id} {hint} {error} {disabled} {required} {hideLabel}>
  {#snippet children(control)}
    <div class="sel">
      <select
        class="sel__native"
        id={control.id}
        disabled={control.disabled}
        required={control.required}
        aria-invalid={control.invalid ? 'true' : undefined}
        aria-describedby={control.describedby}
        bind:value
        onchange={(event) => onchange?.(event.currentTarget.value)}
      >
        {#if placeholder}
          <option value="" disabled>{placeholder}</option>
        {/if}
        {#each options as option (option.value)}
          <option value={option.value} disabled={option.disabled}>{option.label}</option>
        {/each}
      </select>
      <svg class="sel__chev" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path fill="currentColor" d="M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z" />
      </svg>
    </div>
  {/snippet}
</Field>

<style>
  .sel {
    position: relative;
  }

  /*
   * Ruimte rechts voor de chevron; de rest van de vakstijl komt uit Field. Twee
   * klassen diep, anders wint Fields padding-regel op specificiteit.
   */
  .sel .sel__native {
    appearance: none;
    padding-right: 40px;
    cursor: pointer;
  }

  .sel__chev {
    position: absolute;
    right: 14px;
    top: 50%;
    width: 18px;
    height: 18px;
    transform: translateY(-50%);
    color: var(--ink-2);
    pointer-events: none;
  }
</style>
