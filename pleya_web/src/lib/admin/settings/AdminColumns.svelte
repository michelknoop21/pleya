<!--
  De tweekolomsindeling van de instellingenschermen (28 tot 32): een brede
  kolom links en een even brede rechts, op 1600 elk de helft van de inhoud.
  Onder 900 staan ze onder elkaar, links eerst, zoals de smalle northstar
  (31@393) ze tekent.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    left: Snippet;
    right?: Snippet;
  }

  let { left, right }: Props = $props();
</script>

<div class="cols">
  <div class="col">{@render left()}</div>
  {#if right}<div class="col">{@render right()}</div>{/if}
</div>

<style>
  .cols {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    align-items: start;
    gap: 16px;
  }

  .col {
    display: grid;
    gap: 16px;
    min-width: 0;
  }

  @media (max-width: 899px) {
    .cols {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
