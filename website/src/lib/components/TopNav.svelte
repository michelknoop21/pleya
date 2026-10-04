<script lang="ts">
  import { page } from '$app/state';
  import wordmark from '$lib/assets/pleya_wordmark.png';
  let { sticky = false }: { sticky?: boolean } = $props();
  const path = $derived(page.url.pathname);
  const links = [
    { href: '/iphone', label: 'iPhone' },
    { href: '/apple-tv', label: 'Apple TV' },
    { href: '/mac', label: 'Mac' },
    { href: '/docs', label: 'Guide', match: (p: string) => p.startsWith('/docs') },
  ];
</script>

<header class="topnav" class:sticky>
  <div class="inner">
    <a href="/" class="brand"><img src={wordmark} width="1516" height="659" alt="Pleya" /></a>
    <nav aria-label="Site">
      {#each links as l (l.href)}
        <a href={l.href} aria-current={(l.match ? l.match(path) : path === l.href) ? 'page' : undefined}>{l.label}</a>
      {/each}
    </nav>
  </div>
</header>

<style>
  /* Sits over the page hero; the sticky variant stays in flow for long pages. */
  .topnav { position: absolute; inset: 0 0 auto; z-index: 5; color: rgba(244, 241, 236, 0.66); }
  .topnav.sticky { position: sticky; top: 0; height: 4.25rem; backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); background: rgba(0, 0, 0, 0.6); }
  .inner { max-width: 78rem; height: 100%; margin-inline: auto; padding: 1.25rem; display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
  .sticky .inner { padding-block: 0; }
  .brand { flex-shrink: 0; }
  .brand img { display: block; width: 6.4rem; height: auto; }
  nav { display: flex; gap: 1.5rem; font-size: 0.9rem; white-space: nowrap; }
  nav a:hover, nav a[aria-current='page'] { color: #f4f1ec; }
  nav a[aria-current='page'] { text-decoration: underline; text-decoration-color: #ffb020; text-underline-offset: 0.4em; }
  a:focus-visible { outline: 2px solid #ffb020; outline-offset: 4px; border-radius: 6px; }
  @media (min-width: 768px) { .inner { padding-inline: 2rem; } }
  @media (max-width: 559px) {
    nav { gap: 1rem; font-size: 0.85rem; }
    .brand img { width: 5.2rem; }
  }
  nav { padding: .25rem 1rem; border-radius: 999px; background: linear-gradient(135deg,#ffffff16,#ffffff05 55%,#ffffff0c); border: 1px solid #ffffff21; box-shadow: inset 0 1px 0 #ffffff16,0 8px 24px #0003; -webkit-backdrop-filter: blur(22px) saturate(150%); backdrop-filter: blur(22px) saturate(150%); }
  nav a { display: inline-flex; align-items: center; min-height: 44px; }
  @media (max-width: 559px) { nav { padding-inline: .65rem; gap: .65rem; font-size: .78rem; } .brand img { width: 4.5rem; } .inner { gap: .5rem; } }
  @media (max-width: 359px) { .topnav.sticky { height: auto; } .sticky .inner { height: auto; } .inner { flex-wrap: wrap; gap: .3rem; padding-block: .7rem; } nav { width: 100%; justify-content: space-between; gap: .4rem; } }
  @supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) { nav { background: #171719; } }
</style>
