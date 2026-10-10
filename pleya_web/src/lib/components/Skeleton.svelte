<!--
  Eén vlak van een laadskelet, naar `.skel` uit de northstar (web.css,
  pagina 15): een vulling in `--fill` met een zachte glans die erover loopt.

  Een skelet is decoratie. Het staat altijd buiten de toegankelijkheidsboom;
  wat een schermlezer hoort ("bezig met laden") zegt de container eromheen,
  zie SkeletonPage.

  De vormen volgen de echte componenten en niet de mockup waar die afwijken:
  `card` neemt de regelhoogtes van MediaCard over en `hero` de hoogte van
  Hero, via de tokens die die componenten zelf ook lezen. Anders springt de
  pagina zodra de inhoud binnenkomt.
-->
<script lang="ts">
  interface Props {
    kind?: 'block' | 'line' | 'title' | 'card' | 'hero';
    /** Alleen voor `card`: poster (2:3) of breed (16:9), zoals MediaCard. */
    shape?: 'poster' | 'wide';
    /** Breedte als CSS-lengte, voor een regel of titel die korter moet. */
    width?: string | undefined;
    /** Hoogte als CSS-lengte, voor een los blok. */
    height?: string | undefined;
  }

  let { kind = 'block', shape = 'poster', width, height }: Props = $props();
</script>

{#if kind === 'card'}
  <div class="skc" aria-hidden="true">
    <div class="skel skc__art" class:skc__art--wide={shape === 'wide'}></div>
    <div class="skc__caption">
      <div class="skel skc__title"></div>
      <div class="skel skc__meta"></div>
    </div>
  </div>
{:else}
  <div
    class="skel skel--{kind}"
    aria-hidden="true"
    style:width
    style:height
  ></div>
{/if}

<style>
  .skel {
    position: relative;
    overflow: hidden;
    background: var(--fill);
    border-radius: var(--radius-sm);
  }

  .skel::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(
      90deg,
      transparent,
      color-mix(in srgb, var(--text) 6%, transparent),
      transparent
    );
    animation: skel-shimmer 1.2s infinite;
  }

  .skel--block {
    width: 100%;
  }

  /* web.css: .skel.line 14px, ronde kop 7px. */
  .skel--line {
    width: 100%;
    height: 14px;
    border-radius: 7px;
  }

  /* web.css: .skel.title 22 x 220, radius 8. */
  .skel--title {
    width: 220px;
    max-width: 100%;
    height: 22px;
    border-radius: var(--radius-sm);
  }

  /* De hero van vandaag loopt van rand tot rand, zonder ronde hoeken; zijn
     hoogte komt uit dezelfde tokens als Hero.svelte. */
  .skel--hero {
    width: 100%;
    min-height: var(--hero-min-h);
    max-height: 62dvh;
    border-radius: 0;
  }

  /* Kaart: dezelfde opbouw als MediaCard (padding, tussenruimte, regels). */
  .skc {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
    padding: var(--space-quarter) 0;
  }

  .skc__art {
    aspect-ratio: var(--aspect-poster);
  }

  .skc__art--wide {
    aspect-ratio: var(--aspect-episode);
  }

  /* Titel en metaregel staan in MediaCard zonder tussenruimte onder elkaar. */
  .skc__caption {
    display: flex;
    flex-direction: column;
  }

  .skc__title {
    width: 80%;
    height: calc(var(--text-card-title-size) * var(--text-card-line));
    border-radius: 7px;
  }

  .skc__meta {
    width: 50%;
    height: calc(var(--text-card-sub-size) * var(--text-card-line));
    border-radius: 6px;
  }

  @keyframes skel-shimmer {
    from {
      transform: translateX(-100%);
    }
    to {
      transform: translateX(100%);
    }
  }

  /* Zonder beweging blijft de glans staan, zoals in de stilstaande mockup. */
  @media (prefers-reduced-motion: reduce) {
    .skel::after {
      animation: none;
    }
  }
</style>
