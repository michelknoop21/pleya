<!--
  De lijniconen van het beheeroppervlak, letterlijk uit `ICONS` in
  docs/assets/pleya-web-northstar/src/build.mjs (24 bij 24, lijn 2, ronde
  einden). Inline om dezelfde reden als NavIcon: `currentColor` werkt alleen in
  het document, en de CSP staat geen style-attribuut per instantie toe.
  Altijd versiering: de tekst ernaast draagt de betekenis.
-->
<script lang="ts">
  import type { AdminIconName } from '../admin/sections';

  interface Props {
    name: AdminIconName | 'gear' | 'back' | 'chev' | 'chevl' | 'tv' | 'scan' | 'edit' | 'plus' | 'trash' | 'refresh' | 'stop';
    size?: number;
  }

  let { name, size = 18 }: Props = $props();
</script>

{#if name === 'play' || name === 'stop'}
  <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true" focusable="false">
    {#if name === 'stop'}
      <rect fill="currentColor" x="6" y="6" width="12" height="12" rx="2" />
    {:else}
      <path fill="currentColor" d="M8 5v14l11-7z" />
    {/if}
  </svg>
{:else}
  <svg
    viewBox="0 0 24 24"
    width={size}
    height={size}
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    {#if name === 'chart'}
      <path d="M4 20V10M10 20V4M16 20v-8M22 20H2" />
    {:else if name === 'folder'}
      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
    {:else if name === 'drive'}
      <rect x="3" y="6" width="18" height="12" rx="2" /><path d="M7 12h.01M11 12h6" />
    {:else if name === 'activity'}
      <path d="M3 12h4l3-8 4 16 3-8h4" />
    {:else if name === 'people'}
      <circle cx="9" cy="8" r="3.5" /><path
        d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-5-6.3"
      />
    {:else if name === 'image'}
      <rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="8.5" cy="9.5" r="1.5" /><path
        d="m21 16-5-5-8 8"
      />
    {:else if name === 'globe'}
      <circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" />
    {:else if name === 'shield'}
      <path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z" /><path d="m9 12 2 2 4-4" />
    {:else if name === 'cpu'}
      <rect x="6" y="6" width="12" height="12" rx="2" /><path
        d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"
      />
    {:else if name === 'gear'}
      <circle cx="12" cy="12" r="3" /><path
        d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
      />
    {:else if name === 'back'}
      <path d="M19 12H5" /><path d="m11 18-6-6 6-6" />
    {:else if name === 'chev'}
      <path d="m9 6 6 6-6 6" />
    {:else if name === 'chevl'}
      <path d="m15 6-6 6 6 6" />
    {:else if name === 'tv'}
      <rect x="3" y="5" width="18" height="12" rx="2" /><path d="M8 21h8" />
    {:else if name === 'scan'}
      <path
        d="M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3M3 12h18"
      />
    {:else if name === 'edit'}
      <path d="M4 20h4l10-10-4-4L4 16zM13 7l4 4" />
    {:else if name === 'plus'}
      <path d="M12 5v14M5 12h14" />
    {:else if name === 'refresh'}
      <path d="M20 12a8 8 0 1 1-2.3-5.7" /><path d="M20 4v5h-5" />
    {:else if name === 'trash'}
      <path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" />
    {/if}
  </svg>
{/if}

<style>
  svg {
    flex: none;
    display: block;
  }
</style>
