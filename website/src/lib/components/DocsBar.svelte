<script lang="ts">
  import { page } from '$app/state';
  import Logo from './Logo.svelte';

  const current = $derived(page.url.pathname);
</script>

<header class="docs-bar">
  <a class="home" href="/">
    <span class="mark"><Logo alt="Pleya" /></span>
    <span>Pleya</span>
  </a>
  <nav aria-label="Documentation">
    <a href="/docs" aria-current={current.startsWith('/docs') ? 'page' : undefined}>Guide</a>
    <a href="/releases" aria-current={current === '/releases' ? 'page' : undefined}>Release notes</a>
  </nav>
</header>
