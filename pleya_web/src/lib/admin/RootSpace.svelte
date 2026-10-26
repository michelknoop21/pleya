<!--
  De ruimtecel van scherm 24: een smalle balk met het gebruikte deel, en
  eronder "1,1 TB vrij van 6 TB". Amber als er weinig vrij is (`low`). Een root
  die niet gemount is toont een leeg spoor en "onbekend": het contract draagt
  dan geen bruikbare maten. De balk is een `meter` met een naam, zodat een
  schermlezer het gebruikte deel hoort en niet alleen de tekst eronder.
-->
<script lang="ts">
  import { t } from '../i18n';
  import type { RootSpace } from './storage';

  let { space }: { space: RootSpace } = $props();
</script>

<div class="space">
  <div
    class="space__track"
    class:space__track--low={space.low}
    role={space.known ? 'meter' : undefined}
    aria-label={space.known ? space.label : undefined}
    aria-valuemin={space.known ? 0 : undefined}
    aria-valuemax={space.known ? 100 : undefined}
    aria-valuenow={space.known ? space.usedShare : undefined}
    aria-valuetext={space.known ? space.label : undefined}
  >
    {#if space.known}
      <span class="space__fill" style:width="{space.usedShare}%"></span>
    {/if}
  </div>
  <p class="space__text">
    {space.text}{#if space.low}<span class="space__warn">{t('admin.sto.space.low')}</span>{/if}
  </p>
</div>

<style>
  .space {
    min-width: 140px;
  }

  .space__track {
    height: 4px;
    overflow: hidden;
    border-radius: 2px;
    background: var(--fill-2);
  }

  .space__fill {
    display: block;
    height: 100%;
    border-radius: 2px;
    background: var(--ink);
  }

  .space__track--low .space__fill {
    background: var(--amber-graphic);
  }

  .space__text {
    margin: 6px 0 0;
    font-size: 12px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .space__warn {
    display: block;
    color: var(--warn-ink);
  }
</style>
