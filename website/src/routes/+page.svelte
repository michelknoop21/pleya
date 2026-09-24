<script lang="ts">
  import '$lib/components/home/home.css';
  import Hero from '$lib/components/home/Hero.svelte';
  import Unified from '$lib/components/home/Unified.svelte';
  import Reel from '$lib/components/home/Reel.svelte';
  import Devices from '$lib/components/home/Devices.svelte';
  import Share from '$lib/components/home/Share.svelte';
  import Extras from '$lib/components/home/Extras.svelte';
  import Faq from '$lib/components/home/Faq.svelte';
  import Final from '$lib/components/home/Final.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import { faqSchemaMainEntity } from '$lib/content/faqs';
  import { pageMotion } from '$lib/motion';
  import { startHomeMotion } from '$lib/components/home/motion';

  const title = 'Pleya: Your library, the cinematic way';
  const description =
    'Pleya is a cinematic, fast and private client for Plex and Jellyfin. Private TestFlight beta for iPhone, Apple TV and Mac, with on-device recommendations and direct play.';
  const url = 'https://pleya.app/';
  const image = 'https://pleya.app/og/pleya-social.png';

  const softwareAppSchema = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Pleya',
    description,
    url: 'https://pleya.app',
    applicationCategory: 'MultimediaApplication',
    operatingSystem: 'iOS, tvOS, macOS',
    softwareVersion: 'beta',
  };
  const faqSchema = { '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: faqSchemaMainEntity };
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

<div class="home" use:pageMotion={startHomeMotion}>
  <Hero />
  <main>
    <Unified />
    <Reel />
    <Devices />
    <Share />
    <Extras />
    <Faq />
    <Final />
  </main>
</div>
<Footer />
