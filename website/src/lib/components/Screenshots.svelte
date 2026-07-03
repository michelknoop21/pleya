<script lang="ts">
  import ScrollReveal from './ScrollReveal.svelte';
  import CameraIcon from '~icons/heroicons/camera-solid';
</script>

<section id="screenshots" class="screenshots-section">
  <div class="screenshots-inner">
    <ScrollReveal>
      <p class="section-label">Preview</p>
      <h2 class="section-heading">A fresh look, arriving soon</h2>
      <p class="section-description">
        Pleya has its own cinematic interface, redesigned from the ground up. New screenshots and a full gallery
        are on the way while the beta rolls out.
      </p>
    </ScrollReveal>

    <ScrollReveal delay={80}>
      <div class="frame-stage" aria-hidden="true">
        <div class="frame frame-tv">
          <div class="frame-shimmer"></div>
        </div>
        <div class="frame frame-phone">
          <div class="frame-shimmer"></div>
        </div>
      </div>
    </ScrollReveal>

    <ScrollReveal delay={140}>
      <p class="coming-note">
        <CameraIcon />
        <span>New screenshots coming soon</span>
      </p>
    </ScrollReveal>
  </div>
</section>

<style>
  .screenshots-section {
    padding-block: 4rem;
  }

  .screenshots-inner {
    max-width: 64rem;
    margin-inline: auto;
    padding-inline: 1.5rem;
  }

  .section-label {
    margin-bottom: 0.75rem;
    color: var(--color-accent);
    font-size: 0.875rem;
    font-weight: 500;
    letter-spacing: 0.025em;
    line-height: 1.25rem;
    text-transform: uppercase;
  }

  .section-heading {
    margin-bottom: 1rem;
    font-size: 2.25rem;
    font-weight: 700;
    line-height: 2.5rem;
  }

  .section-description {
    max-width: 34rem;
    margin-bottom: 2.5rem;
    color: var(--color-text-muted);
    font-size: 1.125rem;
    line-height: 1.75rem;
  }

  .frame-stage {
    position: relative;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    gap: 1.5rem;
    padding: 2rem 1rem;
  }

  .frame {
    position: relative;
    overflow: hidden;
    border: 1px solid var(--color-border);
    background:
      radial-gradient(120% 120% at 30% 0%, rgba(244, 43, 31, 0.08), transparent 60%),
      var(--color-surface);
  }

  .frame-tv {
    width: min(100%, 34rem);
    aspect-ratio: 16 / 9;
    border-radius: 1rem;
  }

  .frame-phone {
    display: none;
    width: 8rem;
    aspect-ratio: 9 / 19.5;
    border-radius: 1.75rem;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.6);
  }

  .frame-shimmer {
    position: absolute;
    inset: 0;
    background: linear-gradient(
      100deg,
      transparent 20%,
      rgba(255, 255, 255, 0.04) 45%,
      rgba(255, 255, 255, 0.07) 50%,
      rgba(255, 255, 255, 0.04) 55%,
      transparent 80%
    );
    background-size: 200% 100%;
    animation: shimmer 3.2s ease-in-out infinite;
  }

  @keyframes shimmer {
    0% {
      background-position: 150% 0;
    }
    100% {
      background-position: -150% 0;
    }
  }

  .coming-note {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    margin-top: 1.5rem;
    color: var(--color-text-faint);
    font-size: 0.875rem;
    font-weight: 500;
  }

  .coming-note :global(svg) {
    width: 1.125rem;
    height: 1.125rem;
    color: var(--color-accent-2);
  }

  @media (prefers-reduced-motion: reduce) {
    .frame-shimmer {
      animation: none;
    }
  }

  @media (min-width: 640px) {
    .screenshots-section {
      padding-block: 6rem;
    }

    .frame-phone {
      display: block;
    }
  }

  @media (min-width: 768px) {
    .screenshots-section {
      padding-block: 8rem;
    }

    .section-heading {
      font-size: 3rem;
      line-height: 1;
    }
  }
</style>
