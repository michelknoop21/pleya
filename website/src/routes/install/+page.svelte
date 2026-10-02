<script lang="ts">
  import { onMount } from 'svelte';
  import '$lib/components/home/home.css';
  import TopNav from '$lib/components/TopNav.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import tvHome from '$lib/assets/home/tv-home.webp';

  const androidTvApk = 'https://pleya.app/get/android-tv';
  let downloadStarts: number | null = $state(null);

  onMount(() => {
    fetch('/download-counts.json', { cache: 'no-store' })
      .then((response) => response.ok ? response.json() : null)
      .then((data) => {
        if (typeof data?.total === 'number') downloadStarts = data.total;
      })
      .catch(() => {});
  });
</script>

<svelte:head>
  <title>Install Pleya on Google TV</title>
  <meta name="description" content="Unlisted Pleya download for Google TV and Android TV." />
  <meta name="robots" content="noindex, nofollow, noarchive" />
</svelte:head>

<div class="home install">
  <TopNav />

  <main>
    <section class="install-hero" aria-labelledby="install-title">
      <div class="spill" aria-hidden="true"></div>
      <div class="wrap intro">
        <p class="kicker">Unlisted test build · Google TV &amp; Android TV</p>
        <h1 class="big" id="install-title">Your library.<br /><span class="grad">On your TV.</span></h1>
        <p class="lede">The Pleya experience for the big screen. Sign in to Plex or Jellyfin and pick up where you left off.</p>

        <div class="download-actions">
          <a class="cta download-cta" href={androidTvApk} download="Pleya-Android-TV.apk">
            <span aria-hidden="true">↓</span> Download Pleya for TV
          </a>
          <div class="download-meta">
            <strong>Android APK</strong>
            <span>245 MB · Android 7.1 or newer</span>
          </div>
        </div>
        {#if downloadStarts !== null}
          <p class="counter" aria-live="polite">
            {downloadStarts} download {downloadStarts === 1 ? 'start' : 'starts'} since 1 October 2026
          </p>
        {/if}
      </div>

      <figure class="wrap stage">
        <div class="tv"><img src={tvHome} width="1920" height="1080" alt="Pleya's TV home screen with featured media and Continue Watching" /></div>
        <figcaption>Made for the remote. Your films, series and watch progress in one place.</figcaption>
      </figure>
    </section>

    <section class="install-guide wrap" aria-labelledby="guide-title">
      <div>
        <p class="kicker">Getting started</p>
        <h2 class="big" id="guide-title">Three steps.<br />Big screen.</h2>
        <p class="lede">Open this page in a browser on the TV, then use the download button above.</p>
      </div>
      <ol class="steps">
        <li><span class="step-number">01</span><div><h3>Download</h3><p>Save the APK with a TV browser or file manager.</p></div></li>
        <li><span class="step-number">02</span><div><h3>Install</h3><p>Open the file. If asked, allow that browser or file manager to install apps from this source.</p></div></li>
        <li><span class="step-number">03</span><div><h3>Watch</h3><p>Open Pleya and sign in to your Plex or Jellyfin server.</p></div></li>
      </ol>
    </section>

    <div class="wrap fine-print">
      <p>This is a test build. Compatibility can vary by TV device. The counter records download starts, not completed installations.</p>
      <p>This page is unlisted. Anyone with its address can download the APK.</p>
    </div>
  </main>

  <Footer />
</div>

<style>
  .install { min-height: 100vh; }
  .install-hero { position: relative; overflow: hidden; padding-top: clamp(8rem, 14vw, 12rem); }
  .install-hero .spill { top: 0; height: 42rem; opacity: 0.8; }
  .intro, .stage { position: relative; }
  .intro { max-width: 78rem; }
  .intro .big { margin-top: 1.1rem; max-width: 12ch; }
  .intro .lede { margin-top: 1.7rem; max-width: 37rem; }
  .download-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 1rem 1.5rem; margin-top: 2rem; }
  .download-cta { min-height: 3.4rem; justify-content: center; }
  .download-cta span { font-family: var(--font-sans); font-size: 1.25rem; line-height: 0.8; }
  .download-meta { display: grid; gap: 0.1rem; color: var(--muted); font-size: 0.86rem; }
  .download-meta strong { color: var(--ink); font-weight: 600; }
  .counter { min-height: 1.5rem; margin-top: 0.8rem; color: var(--faint); font-size: 0.8rem; }
  .stage { margin-top: clamp(3rem, 7vw, 5rem); }
  .stage .tv { max-width: 69rem; margin-inline: auto; }
  .stage img { width: 100%; }
  .stage figcaption { max-width: 69rem; margin: 1rem auto 0; color: var(--faint); font-size: 0.84rem; }
  .install-guide { display: grid; gap: 3rem; padding-block: clamp(5rem, 9vw, 8rem); }
  .install-guide .big { margin-top: 1rem; font-size: clamp(2.7rem, 6vw, 5.4rem); }
  .install-guide .lede { margin-top: 1.5rem; }
  .steps { display: grid; gap: 0; }
  .steps li { display: grid; grid-template-columns: 3rem 1fr; gap: 1rem; padding: 1.3rem 0; border-top: 1px solid rgba(255, 255, 255, 0.14); }
  .steps li:last-child { border-bottom: 1px solid rgba(255, 255, 255, 0.14); }
  .step-number { color: var(--amber); font-size: 0.85rem; font-weight: 700; font-variant-numeric: tabular-nums; }
  .steps h3 { font-size: 1.32rem; }
  .steps p { max-width: 30rem; margin-top: 0.3rem; color: var(--muted); }
  .fine-print { display: grid; gap: 0.35rem; padding-bottom: 4rem; color: var(--faint); font-size: 0.82rem; }
  @media (min-width: 900px) { .install-guide { grid-template-columns: 1fr 1fr; gap: 5rem; } }
  @media (max-width: 559px) {
    .install-hero { padding-top: 7.5rem; }
    .intro .big { font-size: clamp(3.1rem, 14vw, 5rem); }
    .download-actions { align-items: stretch; }
    .download-cta { width: 100%; }
    .stage { margin-top: 3rem; }
  }
</style>
