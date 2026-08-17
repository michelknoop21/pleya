<script lang="ts">
  import '../docs.css';
  import DocsBar from '$lib/components/DocsBar.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import NoiseOverlay from '$lib/components/NoiseOverlay.svelte';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  let article: HTMLElement | undefined = $state();
  let progress = $state(0);

  // Rendered open, so the chapter list is there on a desktop and without
  // scripting. On a narrow screen it collapses on load, because twenty links
  // above the first paragraph is not a table of contents, it is a wall.
  let navOpen = $state(true);

  $effect(() => {
    navOpen = !window.matchMedia('(max-width: 59.99rem)').matches;
  });

  // Reading progress across the article, not the page: the footer and the
  // chapter nav are not part of what there is to read.
  $effect(() => {
    const target = article;
    if (!target) return;

    const update = () => {
      const start = target.offsetTop;
      const distance = target.offsetHeight - window.innerHeight;
      if (distance <= 0) {
        progress = 1;
        return;
      }
      progress = Math.min(1, Math.max(0, (window.scrollY - start) / distance));
    };

    update();
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('scroll', update);
      window.removeEventListener('resize', update);
    };
  });

  const toc = $derived(data.chapter.headings.filter((h) => h.level === 2 || h.level === 3));
</script>

<svelte:head>
  <title>{data.chapter.title} - Pleya guide</title>
  <meta name="description" content={data.chapter.summary} />
  <link rel="canonical" href="https://pleya.app/docs/{data.chapter.slug}" />
  <meta property="og:type" content="article" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content="{data.chapter.title} - Pleya guide" />
  <meta property="og:description" content={data.chapter.summary} />
  <meta property="og:url" content="https://pleya.app/docs/{data.chapter.slug}" />
  <meta property="og:image" content="https://pleya.app/og/pleya-social.png" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="{data.chapter.title} - Pleya guide" />
  <meta name="twitter:description" content={data.chapter.summary} />
  <meta name="twitter:image" content="https://pleya.app/og/pleya-social.png" />
</svelte:head>

<div class="docs">
  <NoiseOverlay />
  <DocsBar />

  <div class="read-progress" role="presentation">
    <span style="transform: scaleX({progress})"></span>
  </div>

  <main class="docs-shell">
    <div class="chapter-layout">
      <details class="sidebar-mobile" bind:open={navOpen}>
        <summary>
          <span class="material-symbols-rounded" aria-hidden="true">menu_book</span>
          All chapters
        </summary>
        <nav class="sidebar" aria-label="Chapters">
          {#each data.groups as group (group.group)}
            <p class="section-label">{group.group}</p>
            <ul>
              {#each group.chapters as chapter (chapter.slug)}
                <li>
                  <a
                    href="/docs/{chapter.slug}"
                    aria-current={chapter.slug === data.chapter.slug ? 'page' : undefined}
                  >
                    {chapter.title}
                  </a>
                </li>
              {/each}
            </ul>
          {/each}
        </nav>
      </details>

      <article class="prose" bind:this={article}>
        {@html data.chapter.html}

        <nav class="chapter-nav" aria-label="Chapter navigation">
          {#if data.previous}
            <a class="to-previous" href="/docs/{data.previous.slug}">
              <span class="direction">Previous</span>
              {data.previous.title}
            </a>
          {:else}
            <span></span>
          {/if}
          {#if data.next}
            <a class="to-next" href="/docs/{data.next.slug}">
              <span class="direction">Next</span>
              {data.next.title}
            </a>
          {/if}
        </nav>
      </article>

      {#if toc.length}
        <nav class="toc" aria-label="On this page">
          <p class="section-label">On this page</p>
          {#each toc as heading (heading.id)}
            <a href="#{heading.id}" class:depth-3={heading.level === 3}>{heading.text}</a>
          {/each}
        </nav>
      {/if}
    </div>
  </main>

  <Footer />
</div>

<style>
  .chapter-nav :global(.direction) {
    display: block;
  }
</style>
