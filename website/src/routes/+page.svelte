<script lang="ts">
  import Hero from '$lib/components/Hero.svelte';
  import Features from '$lib/components/Features.svelte';
  import Screenshots from '$lib/components/Screenshots.svelte';
  import FAQ from '$lib/components/FAQ.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import NoiseOverlay from '$lib/components/NoiseOverlay.svelte';
  import { faqSchemaMainEntity } from '$lib/content/faqs';

  const title = "Pleya: Your library, the cinematic way";
  const description = "Pleya is a cinematic, fast, and private client for Plex and Jellyfin. Now in TestFlight beta for iPhone, Apple TV, and macOS, with on-device recommendations, HDR, Dolby Vision, and direct play.";
  const url = "https://pleya.app/";
  const image = "https://pleya.app/og/pleya-social.png";

  const softwareAppSchema = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "name": "Pleya",
    "description": description,
    "url": "https://pleya.app",
    "applicationCategory": "MultimediaApplication",
    "operatingSystem": "iOS, tvOS, macOS",
    "softwareVersion": "beta"
  };

  const faqSchema = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": faqSchemaMainEntity
  };
</script>

<svelte:head>
  <title>{title}</title>
  <meta name="description" content={description} />
  <link rel="canonical" href={url} />

  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  <meta property="og:url" content={url} />
  <meta property="og:image" content={image} />

  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={title} />
  <meta name="twitter:description" content={description} />
  <meta name="twitter:image" content={image} />

  {@html `<script type="application/ld+json">${JSON.stringify(softwareAppSchema)}</script>`}
  {@html `<script type="application/ld+json">${JSON.stringify(faqSchema)}</script>`}
</svelte:head>

<NoiseOverlay />
<Hero />
<Screenshots />
<Features />
<FAQ />

<section class="more-reading" aria-labelledby="more-reading-heading">
  <h2 id="more-reading-heading">Still wondering how something works?</h2>
  <p>
    The guide covers every screen in the app, from connecting a server to what to change
    when playback struggles. The release notes list what changed in each build.
  </p>
  <div class="more-links">
    <a class="primary" href="/docs">Read the guide</a>
    <a href="/releases">See what changed</a>
  </div>
</section>

<Footer />

<style>
  .more-reading {
    max-width: 44rem;
    margin-inline: auto;
    padding: 0 1.5rem 4rem;
    text-align: center;
  }

  .more-reading h2 {
    margin-bottom: 0.75rem;
    font-size: 1.5rem;
  }

  .more-reading p {
    color: var(--color-text-muted);
  }

  .more-links {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 0.75rem;
    margin-top: 1.5rem;
  }

  .more-links a {
    padding: 0.625rem 1.25rem;
    border: 1px solid var(--color-border);
    border-radius: 4px;
    font-size: 0.9375rem;
    font-weight: 600;
    transition: border-color 180ms ease, background-color 180ms ease;
  }

  .more-links a:hover {
    border-color: var(--color-accent-glow);
    background: var(--color-surface);
  }

  .more-links .primary {
    border-color: transparent;
    background: var(--gradient-brand);
    color: #0e0e10;
  }

  .more-links .primary:hover {
    filter: brightness(1.08);
  }
</style>
