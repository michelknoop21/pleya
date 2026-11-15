<!--
  Een segmentkeuze: een radiogroep getekend als één capsule met de gekozen
  optie wit. Onder elk segment zit een native radio, net als in Choice: de
  browser levert de pijltjes binnen de groep en één tabstop, en de focusring
  staat op het segment via :has(:focus-visible).

  Een lege `value` betekent dat er nog niets gekozen is; dan is geen segment
  wit. Het raakvlak is 44 hoog (3 rand plus 38). Onder 480 breekt een groep
  van vier naar twee bij twee, want vier woorden passen niet naast elkaar in
  een paneel van 248 breed.
-->
<script lang="ts">
  interface Option {
    value: string;
    label: string;
  }

  interface Props {
    /** De naam van de groep voor een schermlezer, bijvoorbeeld "Recht op Films". */
    label: string;
    options: Option[];
    value: string;
    onchange: (value: string) => void;
  }

  let { label, options, value, onchange }: Props = $props();

  const uid = $props.id();
</script>

<fieldset class="seg" class:seg--wide={options.length > 3} role="radiogroup" aria-label={label}>
  {#each options as option (option.value)}
    <label class="seg__opt" class:seg__opt--on={option.value === value}>
      <input
        class="visually-hidden"
        type="radio"
        name={uid}
        value={option.value}
        checked={option.value === value}
        onchange={() => onchange(option.value)}
      />
      {option.label}
    </label>
  {/each}
</fieldset>

<style>
  .seg {
    display: inline-flex;
    min-width: 0;
    margin: 0;
    padding: 3px;
    border: 0;
    border-radius: var(--radius-pill);
    background: var(--inset-bg);
  }

  .seg__opt {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 38px;
    padding: 0 14px;
    border-radius: var(--radius-pill);
    font-size: 13px;
    font-weight: 500;
    color: var(--ink-2);
    white-space: nowrap;
    cursor: pointer;
    transition:
      background var(--dur-fast) var(--ease),
      color var(--dur-fast) var(--ease);
  }

  .seg__opt--on {
    background: var(--ink);
    color: var(--bg);
  }

  .seg__opt:has(input:focus-visible) {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }

  @media (hover: hover) {
    .seg__opt:not(.seg__opt--on):hover {
      color: var(--ink);
    }
  }

  @media (max-width: 479px) {
    .seg {
      display: grid;
      grid-auto-flow: column;
      grid-auto-columns: minmax(0, 1fr);
      width: 100%;
      border-radius: var(--radius-md);
    }

    .seg--wide {
      grid-auto-flow: row;
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .seg__opt {
      padding: 0 8px;
      border-radius: var(--radius-sm);
    }
  }
</style>
