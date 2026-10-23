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
    onHighlight?: (item: Item) => void;
  }

  let { items, eagerCount = 12, label, onHighlight }: Props = $props();

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
    <li data-item-id={item.id}>
      <MediaCard {item} {shape} {onHighlight} eager={index < eagerCount} />
    </li>
  {/each}
</ul>

<style>
  /*
   * web.css `.grid`: auto-fill op de posterbreedte van het breekpunt, en onder
   * 900 altijd drie kolommen (DESIGN.md hoofdstuk 3). Met `1fr` als maximum
   * wordt een kolom nooit breder dan twee posters plus een tussenruimte, dus
   * een ultrabreed scherm krijgt meer kolommen en geen grotere posters. Het
   * skelet (SkeletonPage) tekent hetzelfde raster.
   */
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--poster-w), 1fr));
    gap: 22px 16px;
  }

  @media (max-width: 899px) {
    .grid {
      grid-template-columns: repeat(3, 1fr);
      gap: 14px 10px;
    }
  }
</style>
