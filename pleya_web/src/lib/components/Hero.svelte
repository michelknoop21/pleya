<!--
  De hero bovenaan Home, op de geometrie van northstar-beeld 01 (web.css
  .hero) zoals specimen v3 hem toont: ingesprongen op de pagina-inzet met de
  heroradius, 21:9 vanaf 1200, 16:9 tussen 900 en 1199, en daaronder een
  portret van 520 hoog met de tekst gecentreerd onderaan. Verhouding en hoogte
  komen uit tokens.css, zodat het skeletheld dezelfde ruimte inneemt.

  De waas over het beeld draait mee met het thema, en dat is niet cosmetisch:
  artwork flipt niet met de modus, dus een zwarte veil onder bijna-zwarte
  lichte-modus-tekst is onleesbaar. De waas mengt daarom altijd met --scrim
  (de achtergrondkleur), de titel staat in --ink en metaregel en synopsis in
  de artworkinkt van het thema, zodat alles samen omslaat.

  "Meer info" staat er altijd en leidt naar de itempagina. Afspelen staat er
  alleen als de aanroeper een bestemming meegeeft (`playHref`): de
  browserspeler is PS-4W en niet vrijgegeven, en een knop die naar niets leidt
  is erger dan geen knop. Zonder afspeelknop is "Meer info" de enige actie en
  vult hij onder 900 de hele breedte.

  Geen segmentindicator en geen rotatie: de indicator is een open designdetail
  (DESIGN.md hoofdstuk 8) en rotatie hoort bij Home (S8). Synopsis en
  leeftijdsbadge draagt `Item` nog niet (PS-7N); de synopsis verschijnt alleen
  als de aanroeper hem meegeeft, zonder plaatshouder ervoor.
-->
<script lang="ts">
  import Artwork from './Artwork.svelte';
  import type { Item } from '../api/types';
  import { formatDuration } from '../util/format';
  import { t, type MessageKey } from '../i18n';

  interface Props {
    item: Item;
    /** Korte inhoud onder de metaregel; zonder waarde geen alinea. */
    summary?: string;
    /** Bestemming van Afspelen; zonder waarde geen afspeelknop. */
    playHref?: string;
    /** Naam van de sectie voor een schermlezer. */
    label?: string;
  }

  let { item, summary, playHref, label = t('home.recentlyAdded') }: Props = $props();

  const artworkId = $derived(item.artwork?.backdrop_id ?? item.artwork?.poster_id);
  // Soort, jaar en duur, zoals de metaregel in beeld 01; genre draagt `Item`
  // nog niet (PS-7N), dus die ontbreekt en er staat geen lege plek voor.
  const meta = $derived(
    [
      t(`hero.kind.${item.kind}` as MessageKey),
      item.year ? String(item.year) : null,
      formatDuration(item.duration_ms)
    ].filter((part): part is string => Boolean(part))
  );
</script>

<section class="hero" class:hero--none={!artworkId} aria-label={label}>
  {#if artworkId}
    <div class="hero__art">
      <Artwork {artworkId} alt="" shape="free" role="backdrop" eager flat>
        {#snippet fallback()}
          <!-- Mislukt laden: het paneel blijft staan, zonder pictogram midden in beeld. -->
          <div class="hero__fail"></div>
        {/snippet}
      </Artwork>
    </div>
    <div class="hero__scrim" aria-hidden="true"></div>
  {/if}
  <div class="hero__body">
    <h1 class="hero__title t-display-face">{item.title}</h1>
    {#if meta.length}
      <p class="hero__meta">
        {#each meta as part, index (index)}
          {#if index > 0}<span class="hero__dot" aria-hidden="true">·</span>{/if}
          <span>{part}</span>
        {/each}
      </p>
    {/if}
    {#if summary}<p class="hero__summary">{summary}</p>{/if}
    <div class="hero__cta">
      {#if playHref}
        <a class="btn hero__btn" href={playHref}>
          <svg
            class="hero__icon hero__icon--fill"
            viewBox="0 0 24 24"
            aria-hidden="true"
            focusable="false"
          >
            <path d="M7 4.5v15l12.5-7.5z" />
          </svg>
          {t('hero.play')}
        </a>
      {/if}
      <a class="btn btn--secondary hero__btn hero__btn--glass" href="/items/{item.id}">
        <svg class="hero__icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 11v6M12 7.5h.01" />
        </svg>
        {t('hero.moreInfo')}
      </a>
    </div>
  </div>
</section>

<style>
  .hero {
    position: relative;
    isolation: isolate;
    margin: 4px var(--inset) 0;
    aspect-ratio: var(--hero-aspect);
    border-radius: var(--radius-hero);
    overflow: hidden;
    background: var(--surface);
    color: var(--ink);
    /* Tekst over artwork: per thema berekend, light donkerder dan --ink-2. */
    --hero-ink: color-mix(
      in srgb,
      var(--on-artwork) calc(var(--on-artwork-ink) * 100%),
      transparent
    );
  }

  /* Geen artwork: het paneel met de haarlijn uit v2, zonder waas, zodat het
     vlak ook op --bg loskomt. Zelfde keuze als de kaart zonder beeld. */
  .hero--none {
    background: var(--panel);
    box-shadow: inset 0 0 0 1px var(--hairline);
  }

  .hero__art {
    position: absolute;
    inset: 0;
    z-index: -2;
  }

  .hero__art :global(.artwork) {
    height: 100%;
  }

  .hero__art :global(.artwork img) {
    object-position: 50% 25%;
  }

  .hero__fail {
    width: 100%;
    height: 100%;
    background: var(--panel);
  }

  /*
   * Twee verlopen, de dekkingen uit web.css .hero .scrim: van links voor de
   * tekstkolom en van onder voor de knoppen. Ze mengen met --scrim zodat het
   * lichte thema wit wast onder zijn donkere tekst, en de dekkingen volgen
   * --scrim-strong en --scrim-mid: light wast harder (0,97 tegen 0,9). In
   * dark komen de factoren uit op de vaste waarden van web.css (92, 55, 85).
   */
  .hero__scrim {
    position: absolute;
    inset: 0;
    z-index: -1;
    background:
      linear-gradient(
        90deg,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-strong) * 102%), transparent) 0%,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-mid) * 89%), transparent) 45%,
        transparent 75%
      ),
      linear-gradient(
        0deg,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-strong) * 94%), transparent) 0%,
        transparent 45%
      );
  }

  .hero__body {
    position: absolute;
    left: 44px;
    right: 44px;
    bottom: 40px;
    max-width: 560px;
  }

  .hero__title {
    margin: 0 0 12px;
    font-size: 48px;
    letter-spacing: 0.12em;
    overflow-wrap: break-word;
  }

  .hero__meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    margin: 0;
    font-size: 15px;
    color: var(--hero-ink);
  }

  .hero__dot {
    color: var(--ink-3);
  }

  .hero__summary {
    margin: 10px 0 0;
    max-width: 520px;
    font-size: 15px;
    line-height: 1.4;
    color: var(--hero-ink);
  }

  .hero__cta {
    display: flex;
    gap: 10px;
    margin-top: 18px;
  }

  .hero__btn {
    gap: 8px;
  }

  /* De glazen capsule uit beeld 01: --fill-2 met vervaging erachter. */
  .hero__btn--glass {
    backdrop-filter: blur(8px);
  }

  .hero__icon {
    width: 18px;
    height: 18px;
    flex: none;
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .hero__icon--fill {
    width: 16px;
    height: 16px;
    fill: currentColor;
    stroke: none;
  }

  @media (max-width: 1199px) {
    .hero__title {
      font-size: 38px;
    }
    .hero__body {
      left: 32px;
      bottom: 28px;
    }
  }

  /* Portret: tekst gecentreerd onderaan, waas alleen van onder, en elke knop
     een gelijk deel van de breedte (één knop dus de volle breedte). */
  @media (max-width: 899px) {
    .hero {
      height: var(--hero-h-narrow);
    }
    .hero__art :global(.artwork img) {
      object-position: 50% 20%;
    }
    .hero__scrim {
      background: linear-gradient(
        180deg,
        transparent 35%,
        color-mix(in srgb, var(--scrim) calc(var(--scrim-mid) * 89%), transparent) 62%,
        color-mix(in srgb, var(--scrim) min(100%, var(--scrim-strong) * 104%), transparent) 100%
      );
    }
    .hero__body {
      left: 16px;
      right: 16px;
      bottom: 16px;
      max-width: none;
      text-align: center;
    }
    /*
     * Meeschalen tussen 22 en 32, zodat een woord als OPPENHEIMER op 360 nog
     * op één regel past; break-word blijft de vangrail voor langere woorden.
     * De spatiëring staat ook ná de laatste letter, dus een gecentreerde
     * titel zou 0,2em naar links hangen; de inzet links compenseert dat.
     */
    .hero__title {
      font-size: clamp(22px, 7vw, 32px);
      letter-spacing: 0.2em;
      padding-inline-start: 0.2em;
    }
    .hero__meta {
      justify-content: center;
      font-size: 14px;
    }
    .hero__summary {
      margin: 8px 6px 0;
      font-size: 14px;
    }
    .hero__cta {
      margin-top: 14px;
    }
    .hero__btn {
      flex: 1;
    }
  }
</style>
