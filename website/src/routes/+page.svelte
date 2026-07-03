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
<Footer />
