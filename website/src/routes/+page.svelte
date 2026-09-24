<script lang="ts">
  import { onMount } from 'svelte';
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
  import { PUBLIC_TESTFLIGHT_URL, WAITLIST_FALLBACK_EMAIL, betaLinkReady } from '$lib/config';
  import { startHomeMotion } from '$lib/components/home/motion';

  const title = 'Pleya: Your library, the cinematic way';
  const description =
    'Pleya is a cinematic, fast and private client for Plex and Jellyfin. Private TestFlight beta for iPhone, Apple TV and Mac, with on-device recommendations and direct play.';
  const url = 'https://pleya.app/';
  const image = 'https://pleya.app/og/pleya-social.png';

  // Until a public TestFlight link exists the one action is the waitlist, a
  // pre-filled mail (there is no webhook). Filling PUBLIC_TESTFLIGHT_URL in
  // config.ts switches every CTA on the page to the beta.
  const cta = betaLinkReady
    ? { href: PUBLIC_TESTFLIGHT_URL, label: 'Join the TestFlight beta', note: 'Opens TestFlight for iPhone, Apple TV and Mac.' }
    : {
        href: `mailto:${WAITLIST_FALLBACK_EMAIL}?subject=${encodeURIComponent('Pleya waitlist')}&body=${encodeURIComponent('Please add me to the Pleya waitlist.')}`,
        label: 'Join the waitlist',
        note: 'Private TestFlight beta. The button opens your mail app with a pre-filled request.',
      };

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

  let root: HTMLElement;
  onMount(() => {
    let stop: (() => void) | undefined;
    let cancelled = false;
    startHomeMotion(root).then((cleanup) => (cancelled ? cleanup() : (stop = cleanup)));
    return () => {
      cancelled = true;
      stop?.();
    };
  });
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

<div class="home" bind:this={root}>
  <Hero {cta} />
  <main>
    <Unified />
    <Reel />
    <Devices />
    <Share />
    <Extras />
    <Faq />
    <Final {cta} />
  </main>
</div>
<Footer />
