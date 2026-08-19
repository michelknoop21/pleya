<!--
  Het posterraster.

  CSS Grid met `auto-fill` en een minimumbreedte per kolom, in plaats van de
  gemeten kolomtelling die de app doet: een browser kan dat zelf, en er is geen
  d-pad die op dezelfde telling moet uitkomen. De minimumbreedte volgt de
  breekpunten uit `GridSizeCalculator` bij de standaarddichtheid.
-->
<script lang="ts">
  import MediaCard from './MediaCard.svelte';
  import type { Item } from '../api/types';

  interface Props {
    items: Item[];
    /** Aantal kaarten dat het beeld meteen mag laden. */
    eagerCount?: number;
    label?: string;
  }

  let { items, eagerCount = 12, label }: Props = $props();

  /**
   * Eén vorm voor het hele raster.
   *
   * Een aflevering krijgt normaal een 16:9-beeld en een film een poster. In een
   * raster naast elkaar levert dat rijen op met twee verschillende hoogtes, en
   * dat leest als een fout. Bestaat het raster volledig uit afleveringen — de
   * kinderen van een seizoen — dan is 16:9 de juiste keuze voor alles; is het
   * gemengd, zoals bij zoeken, dan wint de poster en wordt het bredere beeld
   * bijgesneden.
   */
  const shape = $derived(
    items.length > 0 && items.every((item) => item.kind === 'episode') ? 'wide' : 'poster'
  );
</script>

<ul class="grid" aria-label={label}>
  {#each items as item, index (item.id)}
    <li>
      <MediaCard {item} {shape} eager={index < eagerCount} />
    </li>
  {/each}
</ul>

<style>
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--grid-min, 110px), 1fr));
    gap: var(--space);
  }

  @media (min-width: 600px) {
    .grid {
      --grid-min: 132px;
    }
  }

  @media (min-width: 900px) {
    .grid {
      --grid-min: 150px;
    }
  }

  @media (min-width: 1200px) {
    .grid {
      --grid-min: 168px;
    }
  }

  /*
   * Boven 1600 groeit het raster niet verder in kaartbreedte maar in
   * kolommen. Zonder deze grens rekt `1fr` een poster op een ultrabreed scherm
   * uit tot een halve meter.
   */
  @media (min-width: 1600px) {
    .grid {
      --grid-min: 180px;
      grid-template-columns: repeat(auto-fill, minmax(var(--grid-min), 220px));
      justify-content: start;
    }
  }
</style>
