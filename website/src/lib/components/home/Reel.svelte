<script lang="ts">
  import screen0 from '$lib/assets/home/tv-home-315-glass.webp';
  import screen1 from '$lib/assets/home/tv-movies-315-glass.webp';
  import screen2 from '$lib/assets/home/tv-all-movies-315-glass.webp';
  import screen3 from '$lib/assets/home/tv-series-detail-315-glass.webp';
  import season2 from '$lib/assets/home/tv-series-season2-315-glass.webp';
  import screen4 from '$lib/assets/home/tv-player-information-315-glass.webp';
  import screen5 from '$lib/assets/home/tv-player-video-315-glass.webp';
  import screen6 from '$lib/assets/home/tv-player-audio-315-glass.webp';
  import screen7 from '$lib/assets/home/tv-player-subtitles-315-glass.webp';

  const frames = [
    { src: screen0, alt: "Pleya Home on Apple TV with Liquid Glass navigation and original demo artwork", title: "Pick up where you stopped", text: "The focused title grows and shows how much is left. Your progress follows you to every device.", specs: [] },
    { src: screen1, alt: "Pleya Movies discovery on Apple TV with original demo titles", title: "Your collection, at a glance", text: "Browse two demo collections with the Siri Remote. Original posters and artwork fill the current Pleya build.", specs: [] },
    { src: screen2, alt: "All movies on Apple TV, with a focused poster and Liquid Glass navigation", title: "All movies. One view.", text: "Your complete movie library, sorted by title. A clear focus ring keeps every poster within reach of the remote.", specs: [] },
    { src: screen3, alt: "NORTH series details on Apple TV, showing three episodes with distinct original images", title: "A season ahead", text: "Every episode has its own scene. Move between seasons and episodes without leaving the series. The selected episode stays clear, even from the couch.", specs: [] },
    { src: season2, alt: "NORTH season two on Apple TV, with three different original episode scenes", title: "A new season. New scenes.", text: "Six episodes, six original images. The second season brings the expedition indoors, onto the frozen fjord and back to the harbour.", specs: [] },
    { src: screen4, alt: "The Apple TV player Information tab in a translucent Liquid Glass panel", title: "Know what is playing", text: "The Information tab puts the title, resolution, video codec and audio format together over the picture.", specs: [] },
    { src: screen5, alt: "The Apple TV player Video tab, with aspect ratio, zoom, HDR and playback controls", title: "Make the picture yours", text: "Aspect ratio, zoom, HDR and playback speed share one Video tab. The picture stays visible behind the glass.", specs: [] },
    { src: screen6, alt: "The Apple TV player Audio tab, with track, sync and volume controls", title: "Sound, in one place", text: "Choose an audio track, adjust sync and manage volume from the Audio tab, using the same remote controls.", specs: [] },
    { src: screen7, alt: "The Apple TV player Subtitles tab, with timing and text appearance controls", title: "Subtitles at your fingertips", text: "Change subtitle timing, text size and background from the Subtitles tab. Keep watching while you adjust.", specs: [] },
  ];
</script>

<section class="reel" id="reel" aria-labelledby="reel-title">
  <div class="wrap reel-head">
    <div>
      <p class="kicker">Built for the couch</p>
      <h2 class="big" id="reel-title" data-split>Made for the remote first.</h2>
    </div>
    <p class="lede">
      Every screen on Apple TV is reachable with the Siri Remote's D-pad. These are captures from the current beta build,
      with original demo movies and series.
    </p>
    <p class="links internal"><a href="/apple-tv">Everything on Apple TV</a></p>
  </div>
  <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
  <div class="reel-viewport" data-reel tabindex="0" aria-label="Apple TV screens, scroll sideways">
    <ol class="reel-track" data-track>
      {#each frames as frame (frame.title)}
        <li class="frame">
          <img class="tv" src={frame.src} width="1920" height="1080" loading="lazy" alt={frame.alt} />
          <h3>{frame.title}</h3>
          <p>{frame.text}</p>
          {#each frame.specs as spec (spec)}<span class="spec">{spec}</span>{/each}
        </li>
      {/each}
    </ol>
  </div>
</section>
