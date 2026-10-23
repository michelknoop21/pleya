<!--
  Laadtoestand van een hele pagina, naar northstar 15: een skelet in de maten
  van de echte inhoud in plaats van een spinner midden op het scherm.

  Vier vormen, elk naar de pagina die erna komt:
  - `home`: hero plus twee rails, zoals de startpagina;
  - `grid`: het kaartenraster van een bibliotheek, onder een kop die al staat;
  - `detail`: poster naast titel en regels, zoals een itempagina;
  - `compact`: een titel en een paar regels, voor de schil zolang nog niet
    vaststaat of er een navigatie, een inlogformulier of een setup volgt.

  Toegankelijkheid: de blokken zijn decoratie en hangen buiten de boom. Hun
  container meldt `aria-busy`, en een verborgen statusregel ernaast zegt wat
  de spinner in StateView zei, zodat een schermlezer nog steeds hoort dat er
  geladen wordt. De statusregel staat bewust buiten de bezige container: een
  live region binnen een `aria-busy`-voorouder houdt zijn aankondiging in.

  `heading` zet een verborgen h1 naast de statusregel. Een skelet dat een hele
  pagina vervangt, laat de pagina anders zonder kop (axe:
  `page-has-heading-one`), en wie met koppen navigeert, belandt dan nergens.
  Hij staat om dezelfde reden buiten de bezige container.
-->
<script lang="ts">
  import Skeleton from './Skeleton.svelte';
  import { t } from '../i18n';

  interface Props {
    variant?: 'home' | 'grid' | 'detail' | 'compact';
    /** Wat de schermlezer hoort; standaard de gedeelde laadtekst. */
    label?: string;
    /** Paginanaam als verborgen h1, voor een skelet dat een hele route vult. */
    heading?: string | undefined;
  }

  let { variant = 'home', label = t('loading'), heading }: Props = $props();

  // Genoeg kaarten om een rij op 1600 en een raster op een groot scherm te
  // vullen; wat buiten beeld valt, kost niets.
  const railCards = Array.from({ length: 10 }, (_, index) => index);
  const gridCards = Array.from({ length: 18 }, (_, index) => index);
  const railTitles = ['220px', '160px'];
</script>

<div class="skp skp--{variant}">
  {#if heading}
    <h1 class="visually-hidden">{heading}</h1>
  {/if}
  <p class="visually-hidden" role="status">{label}</p>

  <div class="skp__body" aria-busy="true" aria-hidden="true">
    {#if variant === 'home'}
      <Skeleton kind="hero" />
      <div class="skp__rails">
        {#each railTitles as titleWidth (titleWidth)}
          <div class="skp__rail">
            <div class="skp__rail-head"><Skeleton kind="title" width={titleWidth} /></div>
            <div class="skp__track">
              {#each railCards as index (index)}
                <div class="skp__cell"><Skeleton kind="card" /></div>
              {/each}
            </div>
          </div>
        {/each}
      </div>
    {:else if variant === 'grid'}
      <div class="skp__grid">
        {#each gridCards as index (index)}
          <Skeleton kind="card" />
        {/each}
      </div>
    {:else if variant === 'detail'}
      <div class="skp__detail">
        <div class="skp__poster"><Skeleton kind="block" /></div>
        <div class="skp__lines">
          <Skeleton kind="title" width="60%" />
          <Skeleton kind="line" width="40%" />
          <Skeleton kind="line" width="70%" />
          <Skeleton kind="line" width="55%" />
        </div>
      </div>
    {:else}
      <div class="skp__compact">
        <Skeleton kind="title" />
        <Skeleton kind="line" />
        <Skeleton kind="line" width="70%" />
      </div>
    {/if}
  </div>
</div>

<style>
  /* Dezelfde ruimte als de startpagina en beeld 15: hero, dan elke rij met
     .section erboven (26, onder 900 18). Home leest hetzelfde token; wijkt
     het hier af, dan springt de eerste rij zodra de data binnenkomt. */
  .skp__rails {
    display: flex;
    flex-direction: column;
    gap: var(--section-gap);
    padding-top: var(--section-gap);
  }

  /* De rail volgt HubRail maat voor maat: kop van één raakvlak hoog met 4
     eronder, spoor tot de rand met 6 boven en 4 onder, inzet --inset,
     tussenruimte --rail-gap en een cel van --poster-w. Verandert er daar iets,
     dan hier ook, anders verspringt Home zodra de rij binnenkomt. */
  .skp__rail-head {
    display: flex;
    align-items: center;
    min-height: var(--touch-target);
    margin-bottom: 4px;
    padding-inline: var(--inset);
  }

  .skp__track {
    display: flex;
    gap: var(--rail-gap);
    padding: 6px var(--inset) 4px;
    overflow: hidden;
  }

  .skp__cell {
    flex: 0 0 var(--poster-w);
    width: var(--poster-w);
  }

  /* Het raster volgt MediaGrid. */
  .skp__grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--poster-w), 1fr));
    gap: 22px 16px;
  }

  @media (max-width: 899px) {
    .skp__grid {
      grid-template-columns: repeat(3, 1fr);
      gap: 14px 10px;
    }
  }

  /* De detailkop volgt items/[id]: poster links vanaf 600, regels ernaast. */
  .skp__detail {
    display: grid;
    gap: var(--space-1-5);
    grid-template-columns: 1fr;
    padding: var(--space-1-5) var(--inset);
  }

  @media (min-width: 600px) {
    .skp__detail {
      grid-template-columns: minmax(160px, 240px) 1fr;
      align-items: start;
    }
  }

  /* Op de itempagina staat de poster zonder bijschrift en met de grotere
     radius; een los blok in 2:3 dus, geen kaart. */
  .skp__poster {
    max-width: 240px;
  }

  .skp__poster :global(.skel) {
    aspect-ratio: var(--aspect-poster);
    border-radius: var(--radius-md);
  }

  .skp__lines,
  .skp__compact {
    display: flex;
    flex-direction: column;
    gap: var(--space);
  }

  /* Een smalle kolom, verticaal in de bovenste 40vh, omdat nog onbekend is
     wat er komt: inloggen, setup of de app. Onbereikbaar (14) staat in de schil
     met een eigen opbouw, dus tussen de twee valt geen gedeelde hoogte te
     bewaken. De eerste stap van starten naar onbereikbaar wisselt bewust van
     vorm; elke volgende poging blijft in onbereikbaar (session.start) en komt
     hier niet meer langs, zodat de schil per poging niet verdwijnt. */
  .skp__compact {
    width: min(100%, 360px);
    min-height: 40vh;
    justify-content: center;
    margin-inline: auto;
    padding: var(--space-2);
  }
</style>
