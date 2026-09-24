<script lang="ts">
  import type { Snippet } from 'svelte';

  type Shot = { src: string; w: number; h: number; alt: string; frame: 'tv' | 'phone' | 'mac'; land?: boolean };
  let {
    kicker,
    heading,
    shots,
    flip = false,
    children,
  }: { kicker: string; heading: string; shots: Shot[]; flip?: boolean; children?: Snippet } = $props();
</script>

<section class="pf-feature" class:flip class:text-only={!shots.length}>
  <div class="wrap">
    <div>
      <p class="kicker">{kicker}</p>
      <h2 class="big" data-split>{heading}</h2>
      {@render children?.()}
    </div>
    {#if shots.length}
      <figure data-reveal>
        {#each shots as s, i (i)}
          <img class={s.frame} class:land={s.land} src={s.src} width={s.w} height={s.h} loading="lazy" alt={s.alt} />
        {/each}
      </figure>
    {/if}
  </div>
</section>
