<!--
  Alle primitieven uit S7 in elke staat, op één pagina, als werkbank voor de
  review en als bron voor de screenshots in docs/qa/s7-primitives/. De route
  bestaat alleen in ontwikkeling (+page.ts geeft daarbuiten een 404), en
  daarom zijn de galerijlabels gewone Nederlandse tekst en geen t()-sleutels.

  Een index links (sections.ts) en bovenaan het Overzicht: specimen v2
  nagebouwd met de echte componenten. Daaronder elke primitief per staat.

  `?skeleton=<variant>` toont één SkeletonPage over de hele breedte, zonder
  galerij eromheen, zodat hij naast mockup 15 gelegd kan worden.
-->
<script lang="ts">
  import { page } from '$app/state';

  import SkeletonPage from '$lib/components/SkeletonPage.svelte';
  import ThemePicker from '$lib/components/ThemePicker.svelte';
  import FormSection from './FormSection.svelte';
  import DisplaySection from './DisplaySection.svelte';
  import StructureSection from './StructureSection.svelte';
  import SkeletonSection from './SkeletonSection.svelte';
  import CardSection from './CardSection.svelte';
  import StorageSection from './StorageSection.svelte';
  import OverviewSection from './OverviewSection.svelte';
  import GalleryIndex from './GalleryIndex.svelte';

  const VARIANTS = ['home', 'grid', 'detail', 'compact'] as const;
  type Variant = (typeof VARIANTS)[number];

  const only = $derived.by((): Variant | null => {
    const value = page.url.searchParams.get('skeleton');
    return VARIANTS.find((v) => v === value) ?? null;
  });
</script>

<svelte:head>
  <title>Primitieven</title>
</svelte:head>

{#if only === 'grid'}
  <!-- Het raster krijgt zijn inzet van libraries/[id] (.page), niet van zichzelf. -->
  <div class="gal__library"><SkeletonPage variant="grid" /></div>
{:else if only}
  <SkeletonPage variant={only} />
{:else}
  <div class="gal">
    <GalleryIndex />
    <div class="gal__body">
      <header class="gal__head">
        <h1 class="gal__title">Primitieven</h1>
        <ThemePicker />
      </header>
      <OverviewSection />
      <FormSection />
      <DisplaySection />
      <StorageSection />
      <StructureSection />
      <SkeletonSection />
      <CardSection />
    </div>
  </div>
{/if}

<style>
  /* Specimen v2: zijkolom van 220 met een haarlijn, de inhoud ernaast. */
  .gal {
    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    min-height: 100dvh;
  }

  .gal__body {
    min-width: 0;
    max-width: 1376px;
    padding: 0 var(--inset) var(--space-4);
  }

  .gal__head {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space);
    align-items: center;
    justify-content: space-between;
    padding: 28px 0 var(--space);
  }

  /* Onder 900 wordt de index een strook bovenaan; die is 62 hoog. */
  @media (max-width: 899px) {
    .gal {
      grid-template-columns: minmax(0, 1fr);
      --gal-sticky: 64px;
    }
  }

  .gal__library {
    padding: var(--space-1-5) var(--page-inset, var(--space));
  }

  .gal__title {
    margin: 0;
    font-size: var(--text-headline-size);
    font-weight: 700;
    letter-spacing: -0.02em;
  }
</style>
