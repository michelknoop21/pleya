<script lang="ts">
  import '../docs/docs.css';
  import DocsBar from '$lib/components/DocsBar.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import NoiseOverlay from '$lib/components/NoiseOverlay.svelte';
  import type { SectionKind } from '$lib/server/releases';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  type Filter = 'all' | SectionKind;

  const FILTERS: { key: Filter; label: string }[] = [
    { key: 'all', label: 'Everything' },
    { key: 'new', label: 'New' },
    { key: 'improved', label: 'Improved' },
    { key: 'fixed', label: 'Fixed' }
  ];

  let filter: Filter = $state('all');

  const counts = $derived(
    data.releases.reduce<Record<string, number>>((totals, release) => {
      for (const section of release.sections) {
        totals[section.kind] = (totals[section.kind] ?? 0) + section.count;
        totals.all = (totals.all ?? 0) + section.count;
      }
      return totals;
    }, {})
  );

  // Notes are context on a release, not a change, so they ride along with
  // "Everything" and drop out of every other filter.
  const visible = $derived(
    data.releases
      .map((release) => ({
        ...release,
        sections: release.sections.filter(
          (section) => filter === 'all' || section.kind === filter
        )
      }))
      .filter((release) => release.sections.length > 0)
  );
</script>

<svelte:head>
  <title>Release notes - Pleya</title>
  <meta
    name="description"
    content="What changed in every Pleya build, from the first TestFlight upload in July 2026 to the current one."
  />
  <link rel="canonical" href="https://pleya.app/releases" />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content="Release notes - Pleya" />
  <meta property="og:description" content="What changed in every Pleya build." />
  <meta property="og:url" content="https://pleya.app/releases" />
  <meta property="og:image" content="https://pleya.app/og/pleya-social.png" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="Release notes - Pleya" />
  <meta name="twitter:description" content="What changed in every Pleya build." />
  <meta name="twitter:image" content="https://pleya.app/og/pleya-social.png" />
</svelte:head>

<div class="docs">
  <NoiseOverlay />
  <DocsBar />

  <main class="docs-shell">
    <div class="docs-lede">
      <span class="eyebrow">Release notes</span>
      <h1>What changed, build by build</h1>
      <p>
        Pleya has shipped as a private TestFlight beta since 2 July 2026, so builds are
        numbered continuously while the version stays at 2.8.0.
      </p>
    </div>

    <div class="segmented" role="group" aria-label="Filter changes">
      {#each FILTERS as option (option.key)}
        <button
          type="button"
          aria-pressed={filter === option.key}
          onclick={() => (filter = option.key)}
        >
          {option.label}
          {#if counts[option.key]}<span class="count">{counts[option.key]}</span>{/if}
        </button>
      {/each}
    </div>

    <div class="release-list">
      {#each visible as release (release.id)}
        <section class="release" class:in-development={release.unreleased} id={release.id}>
          <div class="release-head">
            {#if release.unreleased}
              <p class="release-version">In development</p>
              <p class="release-meta">Not in a build yet</p>
            {:else}
              <p class="release-version">{release.version}</p>
              <p class="release-meta">
                Build {release.build} ·
                <time datetime={release.datetime}>{release.date}</time>
              </p>
            {/if}
          </div>

          <div class="release-body">
            {#if release.unreleased}
              <p class="raw-note">
                Landed in the repository and not in a build yet. They reach TestFlight with the
                next one.
              </p>
            {/if}
            {#each release.sections as section (section.kind)}
              <div class="release-section">
                <span class="status-badge {section.kind}">{section.label}</span>
                <div class="prose">{@html section.html}</div>
              </div>
            {/each}
          </div>
        </section>
      {:else}
        <p class="empty-note">Nothing under this filter yet.</p>
      {/each}
    </div>
  </main>

  <Footer />
</div>

<style>
  .segmented .count {
    margin-left: 0.4rem;
    font-size: 0.75rem;
    color: var(--docs-text-faint);
  }

  .raw-note {
    margin: 0;
    font-size: 0.8125rem;
    font-style: italic;
    color: var(--docs-text-faint);
  }
</style>
