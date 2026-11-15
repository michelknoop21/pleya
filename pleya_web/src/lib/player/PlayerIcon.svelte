<!--
  De glyphs van de spelerschil (mockup 50), inline om dezelfde reden als
  NavIcon: `currentColor` werkt alleen in het document, en een masker zou een
  style-attribuut vragen dat de CSP weigert.
-->
<script module lang="ts">
  export type PlayerIconName =
    | 'play'
    | 'pause'
    | 'back'
    | 'rewind'
    | 'forward'
    | 'volume'
    | 'muted'
    | 'cc'
    | 'tracks'
    | 'fullscreen'
    | 'fullscreen-exit'
    | 'close'
    | 'next'
    | 'settings'
    | 'pip';
</script>

<script lang="ts">
  let { name, size = 22 }: { name: PlayerIconName; size?: number } = $props();
</script>

<svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true" focusable="false">
  {#if name === 'play'}
    <path fill="currentColor" d="M8 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z" />
  {:else if name === 'pause'}
    <path fill="currentColor" d="M7 5h3.2v14H7zm6.8 0H17v14h-3.2z" />
  {:else if name === 'back'}
    <path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="m14.5 6-6 6 6 6" />
  {:else if name === 'rewind' || name === 'forward'}
    <g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
      {#if name === 'rewind'}
        <path d="M5.5 8.5A8 8 0 1 1 4 13" /><path d="M5.5 4v4.5H10" />
      {:else}
        <path d="M18.5 8.5A8 8 0 1 0 20 13" /><path d="M18.5 4v4.5H14" />
      {/if}
    </g>
    <text x="12" y="16" text-anchor="middle" font-size="7.5" font-weight="700" fill="currentColor">10</text>
  {:else if name === 'volume' || name === 'muted'}
    <path fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" />
    {#if name === 'volume'}
      <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" />
    {:else}
      <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="m16 9.5 5 5m0-5-5 5" />
    {/if}
  {:else if name === 'cc'}
    <rect x="3" y="5.5" width="18" height="13" rx="2.5" fill="none" stroke="currentColor" stroke-width="2" />
    <path fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" d="M10.5 10.2a2.3 2.3 0 1 0 0 3.6M17 10.2a2.3 2.3 0 1 0 0 3.6" />
  {:else if name === 'tracks'}
    <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M9 7h11M9 12h11M9 17h11" />
    <circle cx="4.5" cy="7" r="1.3" fill="currentColor" /><circle cx="4.5" cy="12" r="1.3" fill="currentColor" /><circle cx="4.5" cy="17" r="1.3" fill="currentColor" />
  {:else if name === 'fullscreen'}
    <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
  {:else if name === 'fullscreen-exit'}
    <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" />
  {:else if name === 'close'}
    <path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" d="m6 6 12 12M18 6 6 18" />
  {:else if name === 'next'}
    <path fill="currentColor" d="M5 5v14l10-7zM17 5h2.5v14H17z" />
  {:else if name === 'settings'}
    <g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1" />
    </g>
  {:else if name === 'pip'}
    <rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="2" />
    <rect x="12" y="11" width="7" height="6" rx="1" fill="currentColor" />
  {/if}
</svg>
