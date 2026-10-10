<!--
  Wat er óp het beeld van een kaart ligt: versiepil, vinkje of nieuw-punt, en
  de voortgangsbalk. Maten uit northstar web.css (.badge-src, .seen, .dot-new,
  .prog) en specimen v3.

  Staat in een eigen bestand zodat MediaCard over structuur en interactie gaat
  en dit over de tekens. De regels die bepalen óf een teken verschijnt
  (gezien, voortgang) staan in util/format.ts; hier wordt alleen getekend.
-->
<script lang="ts">
  import { plural, t } from '../i18n';

  interface Props {
    /** Aantal versies; de pil verschijnt pas boven één. */
    versions: number;
    watched: boolean;
    isNew: boolean;
    /** 0 tot 1, of null zonder voortgang. */
    progress: number | null;
  }

  let { versions, watched, isNew, progress }: Props = $props();
</script>

{#if versions > 1}
  <span class="badge-src">{plural('card.versions', versions)}</span>
{/if}

<!-- Gezien wint van nieuw: een titel die je al zag is niet nieuw voor jou. -->
{#if watched}
  <span class="seen" role="img" aria-label={t('card.watched')}>
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M5 12.5l4.5 4.5L19 7.5" />
    </svg>
  </span>
{:else if isNew}
  <span class="dot-new" role="img" aria-label={t('card.new')}></span>
{/if}

{#if progress !== null}
  <!-- De resterende tijd staat als tekst in het bijschrift; de balk is beeld. -->
  <span class="prog" aria-hidden="true"><i style:width="{progress * 100}%"></i></span>
{/if}

<style>
  .badge-src {
    position: absolute;
    left: 8px;
    top: 8px;
    padding: 3px 8px;
    border-radius: var(--radius-pill);
    background: color-mix(in srgb, var(--art-shade) 62%, transparent);
    color: var(--art-ink);
    font-size: 11px;
    font-weight: 700;
    line-height: 1.35;
    white-space: nowrap;
  }

  .seen {
    position: absolute;
    right: 8px;
    top: 8px;
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: var(--radius-pill);
    background: var(--art-ink);
    color: var(--art-shade);
  }

  .seen svg {
    width: 13px;
    height: 13px;
    fill: none;
    stroke: currentColor;
    stroke-width: 3;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .dot-new {
    position: absolute;
    right: 8px;
    top: 8px;
    width: 9px;
    height: 9px;
    border-radius: var(--radius-pill);
    background: var(--amber);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--art-shade) 50%, transparent);
  }

  .prog {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 4px;
    background: color-mix(in srgb, var(--art-ink) 22%, transparent);
  }

  .prog i {
    display: block;
    height: 100%;
    background: var(--accent);
  }
</style>
