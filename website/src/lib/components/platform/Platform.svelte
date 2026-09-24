<script lang="ts">
  import type { Snippet } from 'svelte';
  import '$lib/components/home/home.css';
  import TopNav from '$lib/components/TopNav.svelte';
  import Final from '$lib/components/home/Final.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import { cta } from '$lib/config';
  import { pageMotion } from '$lib/motion';

  type Shot = { src: string; w: number; h: number; alt: string; frame: 'tv' | 'phone' | 'mac' };
  let {
    title,
    description,
    path,
    kicker,
    heading,
    lede,
    shot,
    children,
  }: { title: string; description: string; path: string; kicker: string; heading: string; lede: string; shot: Shot; children?: Snippet } = $props();

  const url = $derived(`https://pleya.app${path}`);
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
<div class="home pf" use:pageMotion>
  <section class="pf-hero">
    <div class="spill" aria-hidden="true"></div>
    <div class="wrap">
      <p class="kicker">{kicker}</p>
      <h1 class="hero-title" data-split>{heading}</h1>
      <p class="lede">{lede}</p>
      <div class="pf-cta">
        <a class="cta" href={cta.href}>{cta.label}</a>
        <p class="cta-note">{cta.note}</p>
      </div>
      <figure>
        <img class={shot.frame} src={shot.src} width={shot.w} height={shot.h} fetchpriority="high" alt={shot.alt} />
      </figure>
    </div>
  </section>
  <main>
    {@render children?.()}
    <Final />
  </main>
</div>
<Footer />
