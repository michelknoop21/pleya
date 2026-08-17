<script lang="ts">
  import './docs.css';
  import DocsBar from '$lib/components/DocsBar.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import NoiseOverlay from '$lib/components/NoiseOverlay.svelte';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const dateFormat = new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric'
  });

  function formatUpdated(iso: string) {
    const parsed = new Date(iso);
    return Number.isNaN(parsed.valueOf()) ? iso : dateFormat.format(parsed);
  }
</script>

<svelte:head>
  <title>Guide - Pleya</title>
  <meta
    name="description"
    content="The Pleya guide: connecting a Plex or Jellyfin server, profiles, the player, downloads, Live TV, Watch Together, Pleya Share, Apple TV, and every setting explained."
  />
  <link rel="canonical" href="https://pleya.app/docs" />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content="Guide - Pleya" />
  <meta
    property="og:description"
    content="How to use Pleya with your own Plex or Jellyfin server, chapter by chapter."
  />
  <meta property="og:url" content="https://pleya.app/docs" />
  <meta property="og:image" content="https://pleya.app/og/pleya-social.png" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="Guide - Pleya" />
  <meta
    name="twitter:description"
    content="How to use Pleya with your own Plex or Jellyfin server, chapter by chapter."
  />
  <meta name="twitter:image" content="https://pleya.app/og/pleya-social.png" />
</svelte:head>

<div class="docs">
  <NoiseOverlay />
  <DocsBar />

  <main class="docs-shell">
    <div class="docs-lede">
      <span class="eyebrow">Guide</span>
      <h1>How Pleya works</h1>
      <p>
        Twenty chapters covering everything you can see and do, from connecting your first
        server to what to change when playback struggles. Written against the current build.
      </p>
    </div>

    {#if data.recent.length}
      <section class="recent" aria-label="Recently updated">
        <span class="section-label">Recently updated</span>
        <ul>
          {#each data.recent as chapter (chapter.slug)}
            <li>
              <a href="/docs/{chapter.slug}">{chapter.title}</a>
              <time datetime={chapter.updated}>{formatUpdated(chapter.updated)}</time>
            </li>
          {/each}
        </ul>
      </section>
    {/if}

    {#each data.groups as group (group.group)}
      <h2 class="group-heading">{group.group}</h2>
      <div class="chapter-grid">
        {#each group.chapters as chapter, i (chapter.slug)}
          <a
            class="chapter-card"
            href="/docs/{chapter.slug}"
            style="animation-delay: {i * 50}ms"
          >
            <span class="icon-badge" aria-hidden="true">
              <span class="material-symbols-rounded">{chapter.icon}</span>
            </span>
            <span class="chapter-text">
              <span class="ordinal">Chapter {data.ordinals[chapter.slug]}</span>
              <span class="chapter-title">{chapter.title}</span>
              <span class="chapter-summary">{chapter.summary}</span>
            </span>
          </a>
        {/each}
      </div>
    {/each}
  </main>

  <Footer />
</div>

<style>
  .recent {
    margin-bottom: 2.75rem;
    padding: 1rem 1.25rem;
    border: 1px solid color-mix(in srgb, var(--docs-outline) 60%, transparent);
    border-radius: var(--docs-radius-md);
    background: var(--docs-surface);
  }

  .recent .section-label {
    display: block;
    margin-bottom: 0.6rem;
    font-size: 0.6875rem;
    font-weight: 700;
    letter-spacing: 1.1px;
    text-transform: uppercase;
    color: var(--docs-text-faint);
  }

  .recent ul {
    display: grid;
    gap: 0.4rem;
    font-size: 0.875rem;
  }

  .recent li {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 0.5rem;
  }

  .recent a {
    color: var(--docs-text);
  }

  .recent a:hover {
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .recent time {
    color: var(--docs-text-faint);
  }

  /* The landing page reveals sections with an IntersectionObserver. The chapter
     index is the one place that cannot afford it: if the observer never fires,
     and it does not in every crawler or screenshot tool, the whole list of
     chapters is invisible. Same movement, plain CSS, always completes. */
  .chapter-card {
    height: 100%;
    animation: var(--animate-fade-in-up);
  }

  @media (prefers-reduced-motion: reduce) {
    .chapter-card {
      animation: none;
    }
  }
</style>
