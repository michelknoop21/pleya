<script lang="ts">
  import tvRail from '$lib/assets/home/tv-rail.webp';
  import tvDetail from '$lib/assets/home/tv-detail.webp';
  import tvPlayer from '$lib/assets/home/tv-player.webp';
  import tvRecs from '$lib/assets/home/tv-recs.webp';

  const frames = [
    {
      src: tvRail,
      alt: 'Continue Watching on Apple TV, the focused title enlarged with its progress bar',
      title: 'Pick up where you stopped',
      text: 'The focused title grows and shows how much is left. Your progress follows you to every device.',
      specs: [],
    },
    {
      src: tvDetail,
      alt: 'A film page on Apple TV with 4K, Dolby Vision profile 8 and EAC3 5.1 labels',
      title: 'See the version before you press play',
      text: 'Resolution, HDR format and audio are on the page, read from the file itself.',
      specs: ['4K', 'DV P8', 'EAC3 5.1'],
    },
    {
      src: tvPlayer,
      alt: 'The Apple TV player showing Direct play in its header',
      title: 'Direct play, and it says so',
      text: 'The server sends the file untouched. Transcoding only starts when the device or the connection cannot take the original.',
      specs: [],
    },
    {
      src: tvRecs,
      alt: 'The Movies page on Apple TV with a row titled Because you watched Puss in Boots: The Last Wish',
      title: 'Recommendations that stay home',
      text: '"Because you watched" rows are computed on the device from your own history. That profile never leaves it.',
      specs: [],
    },
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
      with a real library behind them.
    </p>
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
