<script lang="ts">
  import Artwork from './Artwork.svelte';

  let { artworkId }: { artworkId: string | null | undefined } = $props();
</script>

{#if artworkId}
  <div class="atmosphere" aria-hidden="true">
    <div class="atmosphere__image"><Artwork {artworkId} alt="" shape="free" eager flat /></div>
  </div>
{/if}

<style>
  .atmosphere {
    position: absolute;
    inset: 0 0 auto;
    height: min(70vh, 700px);
    overflow: hidden;
    pointer-events: none;
    z-index: -1;
    mask-image: linear-gradient(black, transparent);
    opacity: 0.58;
  }

  .atmosphere__image {
    position: absolute;
    inset: -28px;
    filter: blur(14px);
  }

  .atmosphere__image :global(.artwork) {
    height: 100%;
  }
</style>
