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
-->
<script lang="ts">
  import Skeleton from './Skeleton.svelte';
  import { t } from '../i18n';

  interface Props {
    variant?: 'home' | 'grid' | 'detail' | 'compact';
    /** Wat de schermlezer hoort; standaard de gedeelde laadtekst. */
    label?: string;
  }

  let { variant = 'home', label = t('loading') }: Props = $props();

  // Genoeg kaarten om een rij op 1600 en een raster op een groot scherm te
  // vullen; wat buiten beeld valt, kost niets.
  const railCards = Array.from({ length: 10 }, (_, index) => index);
  const gridCards = Array.from({ length: 18 }, (_, index) => index);
  const railTitles = ['220px', '160px'];
</script>

<div class="skp skp--{variant}">
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
  /* Dezelfde ruimte als de startpagina: hero, dan de rails met 24 erboven. */
  .skp__rails {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding-top: var(--space-2);
  }

  /* De rail volgt HubRail: kop van één raakvlak hoog, spoor met dezelfde
     inzet, tussenruimte en celbreedte. */
  .skp__rail {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
  }

  .skp__rail-head {
    display: flex;
    align-items: center;
    min-height: var(--touch-target);
    padding-inline: var(--page-inset, var(--space));
  }

  .skp__track {
    display: flex;
    gap: var(--space);
    padding-inline: var(--page-inset, var(--space));
    padding-block: var(--space-quarter);
    overflow: hidden;
  }

  .skp__cell {
    flex: 0 0 auto;
    width: var(--rail-cell-w);
  }

  /* Het raster volgt MediaGrid. */
  .skp__grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--grid-cell-min), 1fr));
    gap: var(--space);
  }

  @media (min-width: 1600px) {
    .skp__grid {
      grid-template-columns: repeat(auto-fill, minmax(var(--grid-cell-min), 220px));
      justify-content: start;
    }
  }

  /* De detailkop volgt items/[id]: poster links vanaf 600, regels ernaast. */
  .skp__detail {
    display: grid;
    gap: var(--space-1-5);
    grid-template-columns: 1fr;
    padding: var(--space-1-5) var(--page-inset, var(--space));
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

  /* Zelfde hoogte als de StateView die hier eerder stond, zodat de schil niet
     verspringt; een smalle kolom omdat nog onbekend is wat er komt. */
  .skp__compact {
    width: min(100%, 360px);
    min-height: 40vh;
    justify-content: center;
    margin-inline: auto;
    padding: var(--space-2);
  }
</style>
