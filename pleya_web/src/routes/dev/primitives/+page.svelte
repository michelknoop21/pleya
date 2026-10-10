<!--
  Alle primitieven uit S7 in elke staat, op één pagina, als werkbank voor de
  review en als bron voor de screenshots in docs/qa/s7-primitives/. De route
  bestaat alleen in ontwikkeling (+page.ts geeft daarbuiten een 404), en
  daarom zijn de galerijlabels gewone Nederlandse tekst en geen t()-sleutels.

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
  <header class="gal__head">
    <h1 class="t-headline gal__title">Primitieven</h1>
    <ThemePicker />
  </header>
  <FormSection />
  <DisplaySection />
  <StructureSection />
  <SkeletonSection />
{/if}

<style>
  .gal__head {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space);
    align-items: center;
    justify-content: space-between;
    padding: var(--space-2) var(--inset);
  }

  .gal__library {
    padding: var(--space-1-5) var(--page-inset, var(--space));
  }

  .gal__title {
    margin: 0;
  }
</style>
