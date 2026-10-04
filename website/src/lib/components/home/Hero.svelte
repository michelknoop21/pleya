<script lang="ts">
  import PlexIcon from '~icons/simple-icons/plex';
  import JellyfinIcon from '~icons/simple-icons/jellyfin';
  import tvHome from '$lib/assets/home/tv-home-315-glass.webp';
  import iosHome from '$lib/assets/home/ios-home-315-glass.webp';

  import bigP from '$lib/assets/home/big-p-original.png';

  import { cta } from '$lib/config';
</script>

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
    <figure class="hero-stage peek-stage" data-stage data-moment="side">
      <figcaption class="big-p-intro">Hi, I’m <strong>Big P</strong><span>and this is <strong>Pleya.</strong></span></figcaption>
      <div class="peek-side" aria-hidden="true"><img src={bigP} alt="" /></div>
      <img
        class="tv"
        data-screen
        src={tvHome}
        width="1920"
        height="1080"
        fetchpriority="high"
        alt="Pleya Home on Apple TV with TIDE, original demo artwork and Liquid Glass navigation"
      />
      <img class="phone" data-phone src={iosHome} width="603" height="1311" alt="Pleya on iPhone: Home" />
    </figure>
  </div>
</section>
