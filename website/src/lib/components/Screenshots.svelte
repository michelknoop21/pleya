<script lang="ts">
  import ScrollReveal from './ScrollReveal.svelte';
  import introSplash from '$lib/assets/screenshots/intro-splash.webp';
  import introWelcome from '$lib/assets/screenshots/intro-welcome.webp';
  import homeHero from '$lib/assets/screenshots/home-hero-motu.webp';
  import homeContinue from '$lib/assets/screenshots/home-continue.webp';
  import detailBosch from '$lib/assets/screenshots/detail-bosch.webp';
  import episodesBosch from '$lib/assets/screenshots/episodes-bosch.webp';
  import detailThor from '$lib/assets/screenshots/detail-thor.webp';
  import discoverRequests from '$lib/assets/screenshots/discover-requests.webp';
  import discoverSeverance from '$lib/assets/screenshots/discover-severance.webp';
  import discoverNormal from '$lib/assets/screenshots/discover-normal.webp';
  import discoverPrada from '$lib/assets/screenshots/discover-prada.webp';
  import detailGot from '$lib/assets/screenshots/detail-got.webp';
  import episodesGot from '$lib/assets/screenshots/episodes-got.webp';

  const shots = [
    { src: introSplash, alt: 'Pleya launch screen with the animated logo' },
    { src: introWelcome, alt: 'Sign in with Plex or connect to Jellyfin on the Pleya welcome screen' },
    { src: discoverSeverance, alt: 'Pleya home screen with a cinematic Severance featured hero' },
    { src: episodesGot, alt: 'Season and episode browser in Pleya' },
    { src: homeHero, alt: 'Pleya home screen with a cinematic featured hero' },
    { src: homeContinue, alt: 'Continue watching and personalized rows on the Pleya home screen' },
    { src: detailBosch, alt: 'Pleya show detail screen with ratings, cast and episodes' },
    { src: episodesBosch, alt: 'Season and episode browser in Pleya' },
    { src: detailThor, alt: 'Pleya movie detail screen with ratings and playback options' },
    { src: discoverRequests, alt: 'Discover and request new titles from within Pleya' },
    { src: discoverNormal, alt: 'Continue watching with resume progress on the Pleya home screen' },
    { src: detailGot, alt: 'Pleya show detail screen with ratings, cast and episodes' },
    { src: discoverPrada, alt: 'Featured title billboard on the Pleya home screen' },
  ];

  let rail: HTMLDivElement;
  function nudge(dir: number) {
    rail?.scrollBy({ left: dir * rail.clientWidth * 0.8, behavior: 'smooth' });
  }
</script>

<section id="screenshots" class="screenshots-section">
  <div class="ambient-glow" aria-hidden="true"></div>
  <div class="screenshots-inner">
    <ScrollReveal>
      <p class="section-label">Preview</p>
      <h2 class="section-heading">See it in action</h2>
      <p class="section-description">
        From first launch and a one-tap sign-in to a cinematic home for your library —
        featured hero, continue-watching, and rich detail screens. Here it is running on iPhone.
      </p>
    </ScrollReveal>

    <div class="rail-wrap">
      <button class="rail-nav prev" type="button" aria-label="Vorige schermen" on:click={() => nudge(-1)}>‹</button>
      <div class="phone-rail" role="list" bind:this={rail}>
        {#each shots as shot, i (shot.src)}
          <ScrollReveal delay={i * 70} class="phone-reveal">
            <div class="phone" role="listitem" class:raised={i % 2 === 1}>
              <img src={shot.src} alt={shot.alt} loading="lazy" width="828" height="1800" />
            </div>
          </ScrollReveal>
        {/each}
      </div>
      <button class="rail-nav next" type="button" aria-label="Volgende schermen" on:click={() => nudge(1)}>›</button>
    </div>
    <p class="rail-hint">Sleep of gebruik de pijlen — {shots.length} schermen</p>
  </div>
</section>

<style>
  .screenshots-section {
    position: relative;
    padding-block: 6rem;
    overflow: hidden;
  }

  .ambient-glow {
    position: absolute;
    top: 20%;
    left: 50%;
    width: min(900px, 90vw);
    height: 500px;
    transform: translateX(-50%);
    background: radial-gradient(ellipse at center, rgba(229, 20, 15, 0.16), transparent 68%);
    filter: blur(28px);
    pointer-events: none;
    z-index: 0;
  }

  .screenshots-inner {
    position: relative;
    z-index: 1;
    max-width: 1200px;
    margin-inline: auto;
    padding-inline: 1.5rem;
  }

  .section-label {
    text-transform: uppercase;
    letter-spacing: 0.14em;
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--accent, #e5140f);
    margin: 0 0 0.75rem;
  }

  .section-heading {
    font-family: var(--font-display, inherit);
    font-size: clamp(1.9rem, 4vw, 3rem);
    font-weight: 800;
    line-height: 1.05;
    margin: 0 0 1rem;
    color: #fff;
  }

  .section-description {
    max-width: 44ch;
    color: rgba(255, 255, 255, 0.7);
    font-size: 1.05rem;
    line-height: 1.6;
    margin: 0 0 3rem;
  }

  .rail-wrap {
    position: relative;
  }

  /* Edge fades hint that the rail continues past the viewport. */
  .rail-wrap::before,
  .rail-wrap::after {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    width: 4rem;
    z-index: 2;
    pointer-events: none;
  }
  .rail-wrap::before {
    left: 0;
    background: linear-gradient(90deg, var(--color-bg, #0a0a0a), transparent);
  }
  .rail-wrap::after {
    right: 0;
    background: linear-gradient(270deg, var(--color-bg, #0a0a0a), transparent);
  }

  .rail-nav {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    z-index: 3;
    width: 2.75rem;
    height: 2.75rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 9999px;
    background: rgba(20, 16, 16, 0.72);
    backdrop-filter: blur(6px);
    color: #fff;
    font-size: 1.6rem;
    line-height: 1;
    cursor: pointer;
    transition: background 0.2s, border-color 0.2s, transform 0.15s;
  }
  .rail-nav:hover {
    background: rgba(229, 20, 15, 0.85);
    border-color: transparent;
  }
  .rail-nav:active {
    transform: translateY(-50%) scale(0.94);
  }
  .rail-nav.prev {
    left: 0.25rem;
  }
  .rail-nav.next {
    right: 0.25rem;
  }

  .rail-hint {
    margin: 0.75rem 0 0;
    text-align: center;
    font-size: 0.8rem;
    color: rgba(255, 255, 255, 0.4);
  }

  @media (hover: none) {
    /* Touch: swiping is obvious, hide the arrows but keep the hint + fades. */
    .rail-nav {
      display: none;
    }
  }

  .phone-rail {
    display: flex;
    gap: clamp(1rem, 2.5vw, 2rem);
    overflow-x: auto;
    padding: 1.5rem 0.25rem 2rem;
    scroll-snap-type: x mandatory;
    -webkit-overflow-scrolling: touch;
    scrollbar-width: none;
  }
  .phone-rail::-webkit-scrollbar {
    display: none;
  }

  /* ScrollReveal renders a wrapping div; keep phones from shrinking. */
  .phone-rail :global(.phone-reveal) {
    flex: 0 0 auto;
    scroll-snap-align: center;
  }

  .phone {
    width: clamp(200px, 42vw, 250px);
    border-radius: 2rem;
    padding: 0.4rem;
    background: linear-gradient(160deg, #2a2a2a, #0d0d0d);
    box-shadow:
      0 2px 0 rgba(255, 255, 255, 0.06) inset,
      0 30px 60px -20px rgba(0, 0, 0, 0.85);
    transition: transform 0.4s ease;
  }
  .phone.raised {
    transform: translateY(-1.75rem);
  }
  .phone:hover {
    transform: translateY(-0.5rem);
  }
  .phone.raised:hover {
    transform: translateY(-2.25rem);
  }

  .phone img {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 1.65rem;
  }

  @media (max-width: 640px) {
    .phone.raised {
      transform: none;
    }
    .phone.raised:hover {
      transform: translateY(-0.5rem);
    }
  }
</style>
