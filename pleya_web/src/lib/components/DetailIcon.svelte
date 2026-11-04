<script lang="ts">
  let { name }: { name: 'play' | 'back' | 'more' | 'favorite' | 'rating' | 'watched' | 'add' } = $props();
</script>
<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
  {#if name === 'play'}<path d="m8 4 12 8-12 8z" />
  {:else if name === 'back'}<path d="m15 5-7 7 7 7" />
  {:else if name === 'more'}<circle cx="5" cy="12" r=".8" fill="currentColor" /><circle cx="12" cy="12" r=".8" fill="currentColor" /><circle cx="19" cy="12" r=".8" fill="currentColor" />
  {:else if name === 'favorite'}<path d="M6 3h12v18l-6-4-6 4z" />
  {:else if name === 'rating'}<path d="m12 3 2.8 5.8 6.4.9-4.6 4.5 1.1 6.3-5.7-3-5.7 3 1.1-6.3-4.6-4.5 6.4-.9z" />
  {:else if name === 'watched'}<path d="m5 12 4 4L19 6" />
  {:else}<path d="M12 4v16M4 12h16" />{/if}
</svg>
