<script lang="ts">
  import { onMount } from 'svelte';
  import { L, STILL } from './layers';
  import { coreLoaded, mount } from './mount';
  import type { BigP } from './rig';

  let {
    facing = 1,
    enters = false,
    onready,
  }: {
    facing?: 1 | -1;
    /** He walks into view himself, so nothing is drawn until the rig runs. */
    enters?: boolean;
    onready?: (bigp: BigP) => void;
  } = $props();

  let host: HTMLDivElement;
  let live = $state(false);

  onMount(() => {
    let stop: (() => void) | undefined;
    let dead = false;
    coreLoaded().then(() => {
      if (dead) return;
      const m = mount(host, { facing });
      stop = m.destroy;
      live = true;
      onready?.(m.bigp);
    });
    return () => {
      dead = true;
      stop?.();
    };
  });
</script>

<!-- Decorative: what Big P says is always in the text next to him. -->
<div class="bigp" bind:this={host} aria-hidden="true">
  {#if enters}
    <noscript><img src={STILL} alt="" width={L.w} height={L.h} /></noscript>
  {:else if !live}
    <img src={STILL} alt="" width={L.w} height={L.h} loading="lazy" decoding="async" />
  {/if}
</div>

<style>
  .bigp { position: relative; width: 100%; aspect-ratio: 1122 / 1402; pointer-events: none; user-select: none; }
  .bigp :global(img) { position: absolute; inset: 0; width: 100%; height: 100%; }
</style>
