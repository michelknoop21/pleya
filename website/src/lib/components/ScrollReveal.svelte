<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children, delay = 0, class: className = '' }: { children: Snippet; delay?: number; class?: string } = $props();
</script>

<div class="{className} scroll-reveal" style="animation-delay: {delay}ms;">
  {@render children()}
</div>

<style>
  /* Entrance animation in plain CSS, no IntersectionObserver.
     The observer version wrote opacity: 0 into the server-rendered HTML and only
     cleared it once it fired, so anything that never runs the page script kept a
     full-height blank where Screenshots, Features and FAQ belong. Same movement as
     the chapter index on /docs, and it completes on its own.
     Not switched to animation-timeline: view(), which would tie progress to scroll
     position again and leave a full-page capture blank below the fold. */
  .scroll-reveal {
    animation: var(--animate-fade-in-up);
  }

  @media (prefers-reduced-motion: reduce) {
    .scroll-reveal {
      animation: none;
    }
  }
</style>
