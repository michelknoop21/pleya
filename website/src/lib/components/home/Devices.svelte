<script lang="ts">
  import macHome from '$lib/assets/home/mac-home.webp';
  import iosMovies from '$lib/assets/home/ios-movies.webp';
  import iosDetail from '$lib/assets/home/ios-detail.webp';
</script>

<section class="devices" id="devices">
  <div class="wrap">
    <p class="kicker">iPhone and Mac</p>
    <h2 class="big" data-split>The same library in your pocket and on your desk.</h2>
    <figure class="devices-stage">
      <img class="mac" src={macHome} width="1312" height="822" loading="lazy" alt="Pleya on a Mac: Discover, with the collapsed sidebar showing Plex and Pleya Server libraries as icons" />
      <img class="phone p1" src={iosMovies} width="603" height="1311" loading="lazy" alt="Pleya on iPhone: Movies, with a Because you watched row" />
      <img class="phone p2" src={iosDetail} width="603" height="1311" loading="lazy" alt="Pleya on iPhone: a film page with 4K, DV P8 and EAC3 Atmos labels and a Download button" />
    </figure>
    <div class="trio">
      <div><h3>Downloads for the train</h3><p>Download films and episodes and watch them without a connection.</p></div>
      <div>
        <h3>Atmos on AirPods</h3>
        <p>On iPhone, iPad and Apple TV Pleya asks for multichannel audio, which lets Dolby Atmos and spatial audio work on AirPods and receivers.</p>
      </div>
      <div><h3>A profile per person</h3><p>Everyone in the house gets their own profile and history. Settings follow you through iCloud.</p></div>
    </div>
  </div>
</section>
