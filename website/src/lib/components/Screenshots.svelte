<script lang="ts">
  import ScrollReveal from './ScrollReveal.svelte';
  import discoverNormal from '$lib/assets/screenshots/discover-normal.png';
  import discoverSeverance from '$lib/assets/screenshots/discover-severance.png';
  import discoverPrada from '$lib/assets/screenshots/discover-prada.png';
  import detailGot from '$lib/assets/screenshots/detail-got.png';
  import episodesGot from '$lib/assets/screenshots/episodes-got.png';

  const shots = [
    { src: discoverSeverance, alt: 'Pleya home screen with a cinematic featured hero' },
    { src: discoverNormal, alt: 'Continue watching with resume progress on the Pleya home screen' },
    { src: detailGot, alt: 'Pleya show detail screen with ratings, cast and episodes' },
    { src: discoverPrada, alt: 'Featured title billboard on the Pleya home screen' },
    { src: episodesGot, alt: 'Season and episode browser in Pleya' },
  ];
</script>

<section id="screenshots" class="screenshots-section">
  <div class="ambient-glow" aria-hidden="true"></div>
  <div class="screenshots-inner">
    <ScrollReveal>
      <p class="section-label">Preview</p>
      <h2 class="section-heading">See it in action</h2>
      <p class="section-description">
        A cinematic home for your library — a featured hero, continue-watching at a glance,
        and rich detail screens. Here it is running on iPhone.
      </p>
    </ScrollReveal>

    <div class="phone-rail" role="list">
      {#each shots as shot, i (shot.src)}
        <ScrollReveal delay={i * 70} class="phone-reveal">
          <div class="phone" role="listitem" class:raised={i % 2 === 1}>
            <img src={shot.src} alt={shot.alt} loading="lazy" width="828" height="1799" />
          </div>
        </ScrollReveal>
      {/each}
    </div>
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
    background: radial-gradient(ellipse at center, rgba(244, 43, 31, 0.16), transparent 68%);
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
    color: var(--accent, #f42b1f);
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
