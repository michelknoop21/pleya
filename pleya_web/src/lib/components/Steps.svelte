<!--
  De stappenbalk van de setup (`.steps` in web.css, mockup 40 tot 44): een rond
  nummer van 24 px met het label ernaast en een dunne lijn tussen de stappen.
  Afgeronde stappen worden een gevuld rondje met een vinkje, de huidige stap
  krijgt een inktrand en vet label.

  Het is een geordende lijst; de huidige stap draagt aria-current="step" en een
  afgeronde stap zegt "done" voor een schermlezer, omdat het vinkje alleen
  beeld is. Onder 900 houdt alleen de huidige stap zijn label naast het rondje;
  de andere labels blijven voor een schermlezer staan in plaats van weg te
  vallen.
-->
<script lang="ts">
  import { t } from '../i18n';

  interface Props {
    steps: string[];
    /** Index (vanaf 0) van de huidige stap; alles ervoor is afgerond. */
    current: number;
    label?: string;
  }

  let { steps, current, label = t('steps.label') }: Props = $props();
</script>

<ol class="steps" aria-label={label}>
  {#each steps as step, index (index)}
    {@const done = index < current}
    {@const on = index === current}
    <li class="st" class:st--done={done} class:st--on={on} aria-current={on ? 'step' : undefined}>
      <span class="st__n" aria-hidden="true">
        {#if done}
          <svg viewBox="0 0 24 24" width="14" height="14">
            <path fill="none" stroke="currentColor" stroke-width="2.5" d="m5 12.5 4.5 4.5L19 7.5" />
          </svg>
        {:else}
          {index + 1}
        {/if}
      </span>
      <span class="st__label">
        {step}{#if done}<span class="visually-hidden">, {t('steps.done')}</span>{/if}
      </span>
    </li>
  {/each}
</ol>

<style>
  .steps {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0 0 26px;
    padding: 0;
    list-style: none;
    font-size: 13px;
    color: var(--ink-3);
  }

  .st {
    display: flex;
    flex: 0 1 auto;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  /* De lijn tussen twee stappen (`.ln`); een li kan alleen li-kinderen hebben. */
  /* De lijn krimpt mee, anders duwt vijf stappen met een label de laatste
     cirkel op 393 over de rand. */
  .st + .st::before {
    content: '';
    flex: 0 1 auto;
    width: 28px;
    min-width: 12px;
    height: 1px;
    background: var(--hairline-strong);
  }

  .st__n {
    display: grid;
    flex: none;
    place-items: center;
    width: 24px;
    height: 24px;
    border: 1.5px solid var(--ink-4);
    border-radius: var(--radius-pill);
    font-size: 12px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .st--done .st__n {
    border-color: var(--ink);
    background: var(--ink);
    color: var(--bg);
  }

  .st--on {
    font-weight: 600;
    color: var(--ink);
  }

  .st--on .st__n {
    border-color: var(--ink);
  }

  @media (max-width: 899px) {
    .st:not(.st--on) .st__label {
      position: absolute;
      width: 1px;
      height: 1px;
      overflow: hidden;
      clip-path: inset(50%);
      white-space: nowrap;
    }
  }
</style>
