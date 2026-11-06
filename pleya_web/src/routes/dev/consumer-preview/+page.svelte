<script lang="ts">
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { setLocale } from '#lib/i18n/index.js';
  import Hero from '#lib/components/Hero.svelte';
  import HubRail from '#lib/components/HubRail.svelte';
  import MediaCard from '#lib/components/MediaCard.svelte';
  import Wordmark from '#lib/components/Wordmark.svelte';
  import NavIcon from '#lib/components/NavIcon.svelte';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import { setArtworkLoader } from '#lib/components/artworkLoader.js';
  import { cardSubtitle } from '#lib/util/format.js';
  import { featured, recent, continuing, coverTitles, newEpisodes, fixtureParent } from './fixtures';
  import './preview.css';

  setLocale('nl');
  const before = $derived(page.url.searchParams.has('before'));
  let sidebarOpen = $state(true);
  let previewState = $state(untrack(() => page.url.searchParams.get('state') ?? 'populated'));
  // Zonder lokale review-art tekent de preview een vlak met het artwork-id erop,
  // zodat een opname laat zien welk beeld een kaart koos.
  const labelled = (id: string) => {
    const hue = [...id].reduce((sum, ch) => sum + ch.charCodeAt(0), 0) % 360;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="hsl(${hue} 45% 32%)"/><text x="24" y="330" font-family="sans-serif" font-size="34" fill="#fff">${id}</text></svg>`;
    return new Blob([svg], { type: 'image/svg+xml' });
  };
  setArtworkLoader(async (id, signal) => {
    const response = await fetch(`/review-art/${encodeURIComponent(id)}.jpg`, { signal }).catch(() => null);
    if (!response?.ok || !response.headers.get('content-type')?.startsWith('image/')) return labelled(id);
    return response.blob();
  });
</script>

<svelte:head><title>Homevoorstel · Pleya</title></svelte:head>

<div class="consumer-preview" class:consumer-preview--before={before} class:consumer-preview--compact={!sidebarOpen}>
  <aside class="preview-sidebar" aria-label="Pleya navigatie">
    <div class="sidebar-brand"><Wordmark /><img class="sidebar-compact-mark" src="/brand/pleya-mark-64.png" alt="Pleya" /><button type="button" aria-label={sidebarOpen ? "Navigatie inklappen" : "Navigatie uitklappen"} aria-expanded={sidebarOpen} onclick={() => sidebarOpen = !sidebarOpen}><svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 5h16v14H4zM9 5v14" /></svg></button></div>
    <nav aria-label="Desktop hoofdnavigatie">
      <a href="/server" aria-label="Mijn Pleya" class="sidebar-profile"><NavIcon name="person" /><span>Mijn Pleya</span></a>
      <a href="/search" aria-label="Zoeken"><NavIcon name="search" /><span>Zoeken</span></a>
      <a href="/" aria-label="Home" aria-current="page"><NavIcon name="home" /><span>Home</span></a>
      <div class="sidebar-label">Bibliotheken</div>
      <a href="/films" aria-label="Films"><NavIcon name="movie" /><span>Films</span></a>
      <a href="/series" aria-label="Series"><NavIcon name="show" /><span>Series</span></a>
      <a href="/libraries" aria-label="Alle bibliotheken"><NavIcon name="library" /><span>Alle bibliotheken</span></a>
      <div class="sidebar-label">Persoonlijk</div>
      <a href="/server/favorites" aria-label="Favorieten"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M6 3h12v18l-6-4-6 4z" /></svg><span>Favorieten</span></a>
    </nav>
    
  </aside>
  <nav class="preview-nav" aria-label="Hoofdnavigatie">
    <a class="preview-profile" href="/server" aria-label="Mijn Pleya"><NavIcon name="person" /></a>
    <div class="preview-destinations">
      <a href="/search" aria-label="Zoeken"><NavIcon name="search" /></a>
      <a href="/" aria-current="page">Home</a>
      <a href="/series">Series</a><a href="/films">Films</a><a href="/libraries">Bibliotheken</a><a href="/server">Mijn Pleya</a>
    </div>
    <a href="/" class="preview-brand" aria-label="Pleya Home"><Wordmark /></a>
  </nav>

  {#if previewState === 'loading'}
    <SkeletonPage variant="home" heading="Home" />
  {:else if previewState === 'empty'}
    <div class="preview-state"><h1>Home</h1><StateView title="Er is nog niets toegevoegd" message="Bekijk je bibliotheken om verder te gaan."><a class="btn" href="/server">Mijn Pleya</a></StateView></div>
  {:else if previewState === 'error'}
    <div class="preview-state"><h1>Home</h1><StateView kind="error" message="De server is even niet bereikbaar." onRetry={() => previewState = 'populated'} /></div>
  {:else}
    <Hero item={previewState === 'poster' ? { ...featured, artwork: { poster_id: 'dune2-poster' } } : featured} summary={featured.summary ?? undefined} playHref="/items/dune2/play" />
    <div class="preview-feed">
      <HubRail title="Verder kijken" items={continuing} shape={before ? undefined : 'poster'}>
        {#snippet card(item, index, shape)}
          <MediaCard {item} {shape} eager={index < 8} title={coverTitles[item.id]} subtitle={[item.kind === 'episode' ? `A${item.index}` : null, cardSubtitle(item)].filter(Boolean).join(' · ')} />
        {/snippet}
      </HubRail>
      <HubRail title="Volgende afleveringen" items={[continuing[0]!, continuing[2]!]} shape="wide" />
      <HubRail title="Recent toegevoegd · Series" items={newEpisodes} getParent={fixtureParent} />
      <HubRail title="Recent toegevoegd · Films" items={recent} href="/libraries/films">
        {#snippet card(item, _index, shape)}<MediaCard {item} {shape} eager />{/snippet}
      </HubRail>
    </div>
  {/if}

  <nav class="preview-tabs" aria-label="Mobiele hoofdnavigatie">
    <a href="/" aria-current="page"><NavIcon name="home" />Home</a>
    <a href="/series"><NavIcon name="show" />Series</a>
    <a href="/films"><NavIcon name="movie" />Films</a>
    <a href="/libraries"><NavIcon name="library" />Bibliotheken</a>
    <a href="/server"><NavIcon name="person" />Mijn Pleya</a>
  </nav>
</div>

<aside class="preview-review" aria-label="Ontwerpreview">
  <span>Homevoorstel · tvOS als bron · voorbeeldgegevens</span>
  <label>Toestand <select bind:value={previewState}><option value="populated">Gevuld</option><option value="poster">Alleen poster</option><option value="loading">Laden</option><option value="empty">Leeg</option><option value="error">Fout</option></select></label>
  <a href={before ? '/dev/consumer-preview' : '/dev/consumer-preview?before=1'}>{before ? 'Voorstel' : 'Huidige webgeometrie'}</a>
</aside>
