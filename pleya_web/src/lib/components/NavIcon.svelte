<!--
  De navigatieglyphs.

  De paden zijn letterlijk overgenomen uit `assets/icons/nav/<naam>.svg`, de
  bestanden die de app zelf gebruikt. Ze staan hier inline en niet als los
  bestand met een CSS-masker, om twee redenen: `fill="currentColor"` werkt
  alleen wanneer de SVG in het document staat, en een masker vraagt een
  `style`-attribuut per instantie, wat de strikte `style-src 'self'` uit de
  CSP blokkeert.

  Wijzigt een glyph in `assets/icons/nav/`, dan hoort hij hier mee te wijzigen.
-->
<script lang="ts">
  interface Props {
    name: 'home' | 'search' | 'library' | 'settings' | 'movie' | 'show';
    size?: number;
  }

  let { name, size = 22 }: Props = $props();
</script>

<svg
  class="nav-icon"
  viewBox="0 0 24 24"
  width={size}
  height={size}
  aria-hidden="true"
  focusable="false"
>
  {#if name === 'home'}
    <path fill="currentColor" d="M12 3 2 11h3v9h6v-6h2v6h6v-9h3z" />
  {:else if name === 'search'}
    <g fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round">
      <circle cx="11" cy="11" r="6.5" />
      <path d="m20 20-3.5-3.5" />
    </g>
  {:else if name === 'library'}
    <path fill="currentColor" d="M4 6h2v12H4zm3 0h2v12H7zm4 0h9v12h-9zm2 3v6l5-3z" />
  {:else if name === 'settings'}
    <path
      fill="currentColor"
      fill-rule="evenodd"
      d="M8.71 1.5 15.29 1.5 14.35 4.56 17.27 6.25 19.45 3.9 22.74 9.6 19.62 10.31 19.62 13.69 22.74 14.4 19.45 20.1 17.27 17.75 14.35 19.44 15.29 22.5 8.71 22.5 9.65 19.44 6.73 17.75 4.55 20.1 1.26 14.4 4.38 13.69 4.38 10.31 1.26 9.6 4.55 3.9 6.73 6.25 9.65 4.56ZM12 8.1A3.9 3.9 0 1 0 12 15.9A3.9 3.9 0 1 0 12 8.1Z"
    />
  {:else if name === 'movie'}
    <path fill="currentColor" d="M4 4h3l1.5 3h-3zm5 0h3l1.5 3h-3zm5 0h3l1.5 3h-3zM3 9h18v11H3z" />
  {:else if name === 'show'}
    <path fill="currentColor" d="M8.6 2.8 12 6.2l3.4-3.4 1.4 1.4L14.8 6H21v14H3V6h6.2L7.2 4.2zM5 8v10h14V8z" />
  {/if}
</svg>

<style>
  .nav-icon {
    flex: 0 0 auto;
    display: block;
  }
</style>
