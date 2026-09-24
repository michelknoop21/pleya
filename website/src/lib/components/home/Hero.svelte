<script lang="ts">
  import PlexIcon from '~icons/simple-icons/plex';
  import JellyfinIcon from '~icons/simple-icons/jellyfin';
  import wordmark from '$lib/assets/pleya_wordmark.png';
  import tvHome from '$lib/assets/home/tv-home.webp';
  import iosHome from '$lib/assets/home/ios-home.webp';

  let { cta }: { cta: { href: string; label: string; note: string } } = $props();
</script>

<header class="top">
  <div class="wrap">
    <img src={wordmark} alt="Pleya" width="1452" height="659" />
    <nav aria-label="Site">
      <a href="#unified">One library</a>
      <a href="#reel">Apple TV</a>
      <a href="#share">Pleya Share</a>
      <a href="/docs">Guide</a>
    </nav>
  </div>
</header>

<section class="hero" id="top">
  <div class="spill" aria-hidden="true"></div>
  <div class="wrap">
    <h1 class="hero-title">
      <span class="ln"><span>Your library,</span></span>
      <span class="ln"><span class="grad">the cinematic way</span></span>
    </h1>
    <div class="hero-row">
      <p class="lede">
        Pleya plays what is already on your Plex or Jellyfin server, on Apple TV, iPhone and Mac. Direct play first,
        and recommendations worked out on the device instead of on someone else's server.
      </p>
      <div>
        <a class="cta" href={cta.href}>{cta.label}</a>
        <p class="cta-note">{cta.note}</p>
      </div>
    </div>
    <p class="works">
      Works with
      <span><PlexIcon aria-hidden="true" />Plex</span>
      <span><JellyfinIcon aria-hidden="true" />Jellyfin</span>
    </p>
    <figure class="hero-stage" data-stage>
      <img
        class="tv"
        data-screen
        src={tvHome}
        width="1920"
        height="1080"
        fetchpriority="high"
        alt="Pleya on Apple TV: Home, with a full-screen backdrop for The Runner and the Continue Watching row below"
      />
      <img class="phone" data-phone src={iosHome} width="603" height="1311" alt="Pleya on iPhone: Home" />
    </figure>
  </div>
</section>
