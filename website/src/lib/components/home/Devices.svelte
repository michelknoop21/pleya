<script lang="ts">
  import macHome from '$lib/assets/home/mac-home-315.webp';
  import iosMovies from '$lib/assets/home/ios-home-315-glass.webp';
  import iosDetail from '$lib/assets/home/ios-detail-315-glass.webp';
  import bigP from '$lib/assets/home/bigp-blij.png';
</script>

<section class="devices" id="devices">
  <div class="wrap">
    <p class="kicker">iPhone and Mac</p>
    <h2 class="big" data-split>The same library in your pocket and on your desk.</h2>
    <figure class="devices-stage peek-stage" data-moment="ledge">
      <div class="peek-ledge" aria-hidden="true"><img src={bigP} alt="" /></div>
      <img class="mac" src={macHome} width="1920" height="1050" loading="lazy" alt="Current Pleya on Mac, with both original demo collections in one Home" />
      <img class="phone p1" src={iosMovies} width="603" height="1311" loading="lazy" alt="Pleya Home on iPhone with original artwork and Liquid Glass" />
      <img class="phone p2" src={iosDetail} width="603" height="1311" loading="lazy" alt="The TIDE film detail page on iPhone with Liquid Glass controls" />
    </figure>
    <div class="trio" data-reveal>
      <div><h3>Downloads for the train</h3><p>Download films and episodes and watch them without a connection.</p></div>
      <div>
        <h3>Atmos on AirPods</h3>
        <p>On iPhone and Apple TV Pleya asks for multichannel audio, which lets Dolby Atmos and spatial audio work on AirPods and receivers.</p>
      </div>
      <div><h3>A profile per person</h3><p>Everyone in the house gets their own profile and history. Settings follow you through iCloud.</p></div>
    </div>
    <p class="links internal" data-reveal><a href="/iphone">Pleya on iPhone</a><a href="/mac">Pleya on Mac</a></p>
  </div>
</section>
