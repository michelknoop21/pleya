<script lang="ts">
  import '$lib/components/home/home.css';
  import '$lib/components/bigp/bigp.css';
  import TopNav from '$lib/components/TopNav.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import Video from '$lib/components/home/Video.svelte';
  import Final from '$lib/components/home/Final.svelte';
  import BpHero from '$lib/components/bigp/BpHero.svelte';
  import BpAsk from '$lib/components/bigp/BpAsk.svelte';
  import BpBento from '$lib/components/bigp/BpBento.svelte';
  import BpMore from '$lib/components/bigp/BpMore.svelte';
  import BpConfirm from '$lib/components/bigp/BpConfirm.svelte';
  import BpBrain from '$lib/components/bigp/BpBrain.svelte';
  import BpSources from '$lib/components/bigp/BpSources.svelte';
  import { pageMotion } from '$lib/motion';
  import { startBigPMotion } from '$lib/components/bigp/motion';

  const title = 'Big P: the assistant inside Pleya';
  const description =
    'Big P is the Pleya Assistant. Describe a film you half remember, ask about the story without spoilers, or have him scan a library. You connect the language model, and Pleya asks before a sensitive change.';
  const url = 'https://pleya.app/big-p';
  const image = 'https://pleya.app/og/pleya-social.png';
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
</svelte:head>

<TopNav />
<div class="home bp" use:pageMotion={startBigPMotion}>
  <BpHero />
  <main>
    <BpAsk />
    <BpBento />
    <BpMore />
    <BpConfirm />
    <BpBrain />
    <BpSources />
    <Video meet={false} />
    <Final />
  </main>
</div>
<Footer />
