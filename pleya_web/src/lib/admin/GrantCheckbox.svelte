<!--
  Eén vinkje van de rechtenmatrix (scherm 27): een echte checkbox met het vak
  van de northstar eromheen (wit met een zwart vinkje als hij aan staat). Het
  raakvlak is 44 bij 44, het vak zelf 22. De naam is het `label`, bijvoorbeeld
  "Films, Kijken": in een tabel staat geen zichtbaar label naast het vak.
-->
<script lang="ts">
  interface Props {
    checked: boolean;
    label: string;
    disabled?: boolean;
    onchange: (checked: boolean) => void;
  }

  let { checked, label, disabled = false, onchange }: Props = $props();
</script>

<label class="cb" class:cb--disabled={disabled}>
  <input
    type="checkbox"
    class="cb__input"
    {checked}
    {disabled}
    aria-label={label}
    onchange={(event) => onchange(event.currentTarget.checked)}
  />
</label>

<style>
  .cb {
    display: inline-grid;
    place-items: center;
    min-width: var(--touch-target);
    min-height: var(--touch-target);
    margin: -11px;
    cursor: pointer;
  }

  .cb--disabled {
    cursor: not-allowed;
  }

  .cb__input {
    appearance: none;
    position: relative;
    width: 22px;
    height: 22px;
    margin: 0;
    border: 2px solid var(--hairline-strong);
    border-radius: 6px;
    background: transparent;
    cursor: inherit;
  }

  .cb__input:checked {
    border-color: var(--ink);
    background: var(--ink);
  }

  .cb__input:checked::after {
    content: '';
    position: absolute;
    left: 6px;
    top: 2px;
    width: 5px;
    height: 10px;
    border: solid var(--panel);
    border-width: 0 2px 2px 0;
    transform: rotate(45deg);
  }

  .cb__input:disabled {
    opacity: 0.4;
  }

  .cb__input:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }
</style>
