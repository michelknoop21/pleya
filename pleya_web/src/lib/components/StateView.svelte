<!--
  Leeg en fout in de vorm van `.state` uit de northstar (13): een gecentreerde
  kolom van hooguit 460 met icoon, titel, uitleg en daaronder de uitwegen. Laden
  hoort hier niet: dat is een skelet in de maten van de inhoud (SkeletonPage).

  Een paginatitel is geen onderdeel van de staat. De route zet PageHeader
  erboven, zoals in 13 ("Boeken" boven "Nog geen boeken"), en daarom is de
  titel hier een h2. In `compact` staat de staat binnen een sectie die al een
  kop heeft; daar blijft de titel een alinea, zodat de koppenvolgorde klopt.

  `icon` laat een route zijn eigen pictogram zetten (13 een boek, 14 een
  server); zonder snippet blijven de twee standaardpaden. `onRetry` is een
  snelkoppeling voor de meest voorkomende uitweg en wordt een primaire kleine
  capsule; wie meer uitwegen heeft geeft `actions`.

  `level` 1 is voor een staat die de hele pagina is, zoals onbereikbaar (14):
  daar is geen route met een eigen kop, en de titel van de staat is de naam van
  de pagina. `alert` onwaar is voor een staat met iets dat blijft veranderen,
  zoals een aftelling: binnen een alert zou een schermlezer elke tik voorlezen.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { t } from '../i18n';

  interface Props {
    kind?: 'empty' | 'error';
    title?: string;
    message?: string;
    onRetry?: (() => void) | undefined;
    retryLabel?: string;
    compact?: boolean;
    /** Kopniveau van de titel; 1 alleen als de staat de hele pagina is. */
    level?: 1 | 2;
    /** Een fout is standaard een alert; uit voor een staat met een aftelling. */
    alert?: boolean;
    icon?: Snippet;
    /** Uitleg met opmaak, op de plek van `message` (14 zet de host in mono). */
    body?: Snippet;
    actions?: Snippet;
    children?: Snippet;
  }

  let {
    kind = 'empty',
    title,
    message,
    onRetry,
    retryLabel = t('common.retry'),
    compact = false,
    level = 2,
    alert,
    icon,
    body,
    actions,
    children
  }: Props = $props();

  const resolvedTitle = $derived(
    title ?? (kind === 'error' ? t('states.errorTitle') : t('states.emptyTitle'))
  );
</script>

<div
  class="state"
  class:state--compact={compact}
  role={(alert ?? kind === 'error') ? 'alert' : undefined}
>
  <span class="state__icon" aria-hidden="true">
    {#if icon}
      {@render icon()}
    {:else}
      <svg viewBox="0 0 24 24" focusable="false">
        {#if kind === 'error'}
          <path fill="currentColor" d="M12 2 1 21h22zm0 5 8.5 12h-17zm-1 4v5h2v-5zm0 6v2h2v-2z" />
        {:else}
          <path
            fill="currentColor"
            d="M3 5h18v9h-5a4 4 0 0 1-8 0H3zm2 2v5h4.5a2.5 2.5 0 0 0 5 0H19V7zM3 16h18v3H3z"
          />
        {/if}
      </svg>
    {/if}
  </span>

  {#if compact}
    <p class="state__title">{resolvedTitle}</p>
  {:else if level === 1}
    <h1 class="state__title">{resolvedTitle}</h1>
  {:else}
    <h2 class="state__title">{resolvedTitle}</h2>
  {/if}
  {#if message}
    <p class="state__message">{message}</p>
  {/if}
  {#if body}
    <div class="state__body">{@render body()}</div>
  {/if}
  {#if onRetry || actions}
    <div class="state__actions">
      {#if onRetry}
        <button type="button" class="btn btn--sm state__retry" onclick={onRetry}>
          {retryLabel}
        </button>
      {/if}
      {#if actions}
        {@render actions()}
      {/if}
    </div>
  {/if}
  {#if children}
    <div class="state__extra">{@render children()}</div>
  {/if}
</div>

<style>
  .state {
    max-width: 460px;
    margin: 0 auto;
    padding: 64px 24px;
    text-align: center;
    color: var(--ink-2);
  }

  .state--compact {
    padding: var(--space-2) var(--space);
  }

  .state__icon {
    display: block;
    width: 44px;
    height: 44px;
    margin: 0 auto 14px;
    color: var(--ink-3);
  }

  /* Een meegegeven pictogram vult hetzelfde vak als het standaardpad. */
  .state__icon :global(svg) {
    display: block;
    width: 100%;
    height: 100%;
  }

  .state--compact .state__icon {
    width: 32px;
    height: 32px;
    margin-bottom: 10px;
  }

  .state__title {
    margin: 0;
    font-size: 20px;
    font-weight: 700;
    line-height: 1.25;
    color: var(--ink);
  }

  .state--compact .state__title {
    font-size: 16px;
  }

  .state__message {
    margin: 8px 0 0;
    font-size: 14px;
    line-height: 1.45;
  }

  .state__actions {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
    justify-content: center;
    margin-top: 18px;
  }

  /* Een kleine capsule is 36 hoog, het raakvlak moet 44 zijn. Een onzichtbare
     laag eromheen vergroot het raakvlak zonder de rij te laten verspringen;
     min(0px, ...) laat een knop die al groter is ongemoeid. Ook voor knoppen
     uit `actions`, want die zijn in 13 net zo klein. 4 boven en onder blijft
     binnen de halve rijafstand van 10, dus twee knoppen overlappen niet. */
  .state__actions :global(.btn--sm) {
    position: relative;
  }

  .state__actions :global(.btn--sm)::before {
    content: '';
    position: absolute;
    inset-block: min(0px, calc((100% - var(--touch-target)) / 2));
    inset-inline: min(0px, calc((100% - var(--touch-target)) / 2));
  }

  /* Een toelichting onder de uitwegen, zoals de hulpregel in 13: daar wint
     `.state p` (14) van `.help` (12), dus de maat van de uitleg in --ink-3. */
  .state__extra {
    margin-top: 22px;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
