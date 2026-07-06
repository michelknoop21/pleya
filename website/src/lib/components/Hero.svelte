<script lang="ts">
  import DownloadButtons from "./DownloadButtons.svelte";
  import Waitlist from "./Waitlist.svelte";
  import Logo from "./Logo.svelte";
  import wordmark from "$lib/assets/pleya_wordmark.png";
</script>

<section id="home" class="hero-section">
  <!-- Giant background P-mark watermark -->
  <div class="hero-watermark" aria-hidden="true">
    <Logo />
  </div>

  <!-- Ambient red → amber glow -->
  <div class="ambient-glow" aria-hidden="true"></div>

  <div class="hero-content">
    <img
      src={wordmark}
      alt="Pleya"
      class="hero-wordmark fade-in"
      width="1452"
      height="659"
      fetchpriority="high"
      style="animation-delay: 0ms;"
    />

    <h1 class="hero-title fade-in" style="animation-delay: 100ms;">
      <span class="title-line">Your library,</span>
      <span class="title-line gradient-text">the cinematic way</span>
    </h1>

    <p class="hero-description fade-in" style="animation-delay: 200ms;">
      Pleya turns your Plex or Jellyfin server into a rich, cinema-like
      experience: fast, private, and gorgeous on every screen. Your taste stays
      yours: recommendations are computed on your device and never leave it.
    </p>

    <p class="platform-line fade-in" style="animation-delay: 260ms;">
      <span class="beta-badge">Beta</span>
      Now on iPhone, Apple TV &amp; macOS. More platforms coming.
    </p>

    <div class="hero-cta fade-in" style="animation-delay: 340ms;">
      <DownloadButtons />
    </div>

    <div class="hero-waitlist fade-in" style="animation-delay: 420ms;">
      <Waitlist />
    </div>
  </div>
</section>

<style>
  .hero-section {
    position: relative;
    display: flex;
    min-height: 100dvh;
    align-items: center;
    overflow: hidden;
    background:
      radial-gradient(120% 90% at 80% 0%, rgba(229, 20, 15, 0.1), transparent 55%),
      radial-gradient(90% 80% at 100% 100%, rgba(246, 143, 22, 0.08), transparent 60%),
      var(--color-bg);
  }

  .hero-watermark {
    position: absolute;
    top: 50%;
    right: -18%;
    width: 34rem;
    max-width: 90vw;
    transform: translateY(-50%);
    opacity: 0.05;
    pointer-events: none;
    user-select: none;
  }

  .ambient-glow {
    position: absolute;
    top: 20%;
    right: 8%;
    width: 30rem;
    height: 30rem;
    max-width: 80vw;
    border-radius: 9999px;
    background: var(--gradient-brand);
    opacity: 0.16;
    filter: blur(130px);
    animation: pulse-glow 6s ease-in-out infinite;
    pointer-events: none;
  }

  .hero-content {
    position: relative;
    width: 100%;
    max-width: 72rem;
    margin-inline: auto;
    padding: 6rem 1.5rem;
  }

  .fade-in {
    animation: fade-in-up 0.6s ease-out both;
  }

  .hero-wordmark {
    width: clamp(12rem, 42vw, 19rem);
    height: auto;
    margin-bottom: 2rem;
  }

  .hero-title {
    font-size: clamp(2.25rem, 7vw, 4.25rem);
    line-height: 1.02;
    font-weight: 700;
    letter-spacing: -0.03em;
    max-width: 18ch;
  }

  .title-line {
    display: block;
  }

  .gradient-text {
    color: transparent;
    background: var(--gradient-brand);
    -webkit-background-clip: text;
    background-clip: text;
  }

  .hero-description {
    max-width: 42ch;
    margin-top: 1.5rem;
    color: var(--color-text-muted);
    font-size: clamp(1rem, 2.5vw, 1.1875rem);
    line-height: 1.6;
  }

  .platform-line {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.625rem;
    margin-top: 1.5rem;
    color: var(--color-text-faint);
    font-size: 0.875rem;
    font-weight: 500;
  }

  .beta-badge {
    display: inline-flex;
    align-items: center;
    padding: 0.1875rem 0.5rem;
    border-radius: 9999px;
    background: var(--gradient-brand);
    color: #fff;
    font-size: 0.6875rem;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .hero-cta {
    margin-top: 2.5rem;
  }

  .hero-waitlist {
    margin-top: 2.5rem;
    padding-top: 2rem;
    border-top: 1px solid color-mix(in srgb, var(--color-border) 70%, transparent);
  }

  @media (prefers-reduced-motion: reduce) {
    .fade-in,
    .ambient-glow {
      animation: none;
    }
  }

  @media (min-width: 1024px) {
    .hero-content {
      padding-inline: 3rem;
    }

    .hero-description {
      font-size: 1.25rem;
    }
  }
</style>
