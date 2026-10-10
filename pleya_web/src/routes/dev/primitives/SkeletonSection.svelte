<!-- Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen in ontwikkeling. -->
<script lang="ts">
  import Skeleton from '$lib/components/Skeleton.svelte';
  import SkeletonPage from '$lib/components/SkeletonPage.svelte';
  import Artwork from '$lib/components/Artwork.svelte';
  import GallerySection from './GallerySection.svelte';

  const variants = ['home', 'grid', 'detail', 'compact'] as const;
</script>

<GallerySection id="skelet" title="Skelet">
  <div class="gs__row">
    <div class="sk__cell sk__cell--wide">
      <p class="gs__caption">Regels en titel</p>
      <Skeleton kind="title" width="60%" />
      <Skeleton kind="line" />
      <Skeleton kind="line" width="80%" />
      <Skeleton kind="block" height="64px" />
    </div>
    <div class="sk__cell">
      <p class="gs__caption">Kaart, poster</p>
      <Skeleton kind="card" />
    </div>
    <div class="sk__cell">
      <p class="gs__caption">Artwork zonder beeld</p>
      <!-- Naast de posterkaart, om --fill (skelet) en --skeleton (artwork) te vergelijken. -->
      <Artwork artworkId={null} alt="" eager />
    </div>
    <div class="sk__cell sk__cell--wide">
      <p class="gs__caption">Kaart, breed</p>
      <Skeleton kind="card" shape="wide" />
    </div>
  </div>
  <div>
    <p class="gs__caption">Hero</p>
    <Skeleton kind="hero" />
  </div>

  {#each variants as variant (variant)}
    <div>
      <p class="gs__caption">SkeletonPage {variant}</p>
      <div class="sk__frame">
        <SkeletonPage {variant} />
      </div>
    </div>
  {/each}
</GallerySection>

<style>
  .sk__cell {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    width: 150px;
  }

  .sk__cell--wide {
    width: 280px;
  }

  .sk__frame {
    max-height: 520px;
    overflow: hidden;
    border: 1px solid var(--fill);
    border-radius: var(--radius-card);
  }
</style>
