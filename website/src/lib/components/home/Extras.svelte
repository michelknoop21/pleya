<script lang="ts">
  import { SOURCE_REPO_URL } from '$lib/config';
</script>

<section class="more" id="more">
  <div class="wrap">
    <p class="kicker">More ways to watch</p>
    <div class="cols" data-reveal>
      <div><h3>Watch Together</h3><p>Share a five-character code. Play, pause and seek stay in step for everyone on the same server; the relay passes sync messages only.</p></div>
      <div><h3>Requests</h3><p>Run Jellyseerr or Overseerr? Search, request and follow a title from pending to available inside Pleya.</p></div>
      <div><h3>Live TV</h3><p>If your server has a tuner, watch live channels and record programmes from the same app.</p></div>
    </div>
  </div>
</section>

<section class="open" id="open">
  <div class="wrap">
    <p class="kicker">Open and private</p>
    <h2 class="big" data-split>Nothing to opt out of.</h2>
    <div class="cols" data-reveal>
      <div><h3>GPL-3.0</h3><p>Free software, based on the open-source Plezy client. Pleya's own source is public.</p></div>
      <div><h3>No Pleya account</h3><p>You sign in to your own server. There is no analytics call in the app.</p></div>
      <div><h3>Local taste</h3><p>Recommendations are computed on the device and the profile never leaves it.</p></div>
    </div>
    <p class="links" data-reveal>
      <a href={SOURCE_REPO_URL} target="_blank" rel="noopener noreferrer">Source code</a>
      <a href="/releases">Release notes</a>
      <a href="/docs">The guide</a>
      <a href="/LICENSE.txt">Licence</a>
    </p>
  </div>
</section>
