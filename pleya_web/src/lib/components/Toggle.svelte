<!--
  Een aan/uit-schakelaar (`.toggle` in web.css): spoor van 46 bij 28 op
  --elevated, groen (--ok-ink, in light donkerder) als hij aan staat, met een
  witte knop.

  Het is een button met role="switch" en aria-checked, geen checkbox: een
  schakelaar werkt direct, een checkbox wacht op een formulier. Spatie en Enter
  komen gratis met de button. Het label staat links en is een <label for>,
  zodat een klik op de tekst ook schakelt; de omschrijving hangt er via
  aria-describedby aan en zit dus niet in de naam.
-->
<script lang="ts">
  interface Props {
    label: string;
    checked?: boolean;
    description?: string;
    id?: string;
    disabled?: boolean;
    onchange?: (checked: boolean) => void;
  }

  let {
    label,
    checked = $bindable(false),
    description,
    id,
    disabled = false,
    onchange
  }: Props = $props();

  const uid = $props.id();
  const switchId = $derived(id ?? `${uid}-switch`);
  const labelId = $derived(`${switchId}-label`);
  const descriptionId = $derived(`${switchId}-description`);

  function flip(): void {
    if (disabled) return;
    checked = !checked;
    onchange?.(checked);
  }
</script>

<div class="tgl" class:tgl--dis={disabled}>
  <div class="tgl__text">
    <label class="tgl__label" id={labelId} for={switchId}>{label}</label>
    {#if description}
      <p class="tgl__desc" id={descriptionId}>{description}</p>
    {/if}
  </div>

  <button
    type="button"
    class="tgl__hit"
    id={switchId}
    role="switch"
    aria-labelledby={labelId}
    aria-checked={checked}
    aria-describedby={description ? descriptionId : undefined}
    {disabled}
    onclick={flip}
  >
    <span class="tgl__track" class:tgl__track--on={checked} aria-hidden="true">
      <span class="tgl__knob"></span>
    </span>
  </button>
</div>

<style>
  .tgl {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space);
    min-height: var(--touch-target);
  }

  .tgl__text {
    min-width: 0;
  }

  .tgl__label {
    display: block;
    font-size: 14px;
    font-weight: 600;
    color: var(--ink);
    cursor: pointer;
  }

  .tgl__desc {
    margin-top: 3px;
    font-size: 13px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  /* Het raakvlak is 44 px, het spoor eromheen tekent er 46 bij 28 in. */
  .tgl__hit {
    flex: none;
    display: grid;
    place-items: center;
    min-width: var(--touch-target);
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    border-radius: var(--radius-pill);
    background: none;
    cursor: pointer;
  }

  .tgl__hit:focus-visible {
    outline: none;
  }

  .tgl__hit:focus-visible .tgl__track {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
  }

  .tgl__track {
    position: relative;
    width: 46px;
    height: 28px;
    border-radius: var(--radius-pill);
    background: var(--elevated);
    transition: background var(--dur-fast) var(--ease);
  }

  /*
   * --ok-ink en niet --ok: op donker is dat dezelfde groen, in light een
   * donkerder groen, want de witte knop haalt op #3dd68c maar 1,9:1 en op
   * #0c6b3c 6,6:1 (WCAG 1.4.11, de staat moet zichtbaar zijn).
   */
  .tgl__track--on {
    background: var(--ok-ink);
  }

  .tgl__knob {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 22px;
    height: 22px;
    border-radius: var(--radius-pill);
    /*
     * Uit is de knop gedimde inkt op het verhoogde spoor (specimen v2), zodat
     * uit en aan ook zonder groen verschillen. Aan is hij wit in elk thema,
     * ook in licht (web.css `.toggle i`).
     */
    background: color-mix(in srgb, var(--ink) 72%, var(--bg));
    transition:
      transform var(--dur-fast) var(--ease),
      background var(--dur-fast) var(--ease);
  }

  .tgl__track--on .tgl__knob {
    background: #fff;
    transform: translateX(18px);
  }

  .tgl--dis {
    opacity: 0.5;
  }

  .tgl--dis .tgl__label,
  .tgl--dis .tgl__hit {
    cursor: not-allowed;
  }

  @media (prefers-reduced-motion: reduce) {
    .tgl__track,
    .tgl__knob {
      transition: none;
    }
  }
</style>
