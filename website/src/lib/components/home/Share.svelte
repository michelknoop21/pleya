<script lang="ts">
  import macShare from '$lib/assets/home/mac-share-315.webp';
  import iosHome from '$lib/assets/home/ios-home-315-glass.webp';

  const routes = [
    ['Same Wi-Fi', 'Direct, over the local network.'],
    ['Wi-Fi Aware', 'A direct link with no router or hotspot, on iOS 26.'],
    ['Hotspot', 'The addresses in the QR code plus the hotspot gateway.'],
    ['Cable', 'Ethernet adapters or USB tethering, over link-local addressing.'],
    ['Anywhere', 'An end-to-end encrypted relay when both devices are online on different networks.'],
  ];
</script>

<section class="share" id="share">
  <div class="wrap">
    <div class="share-grid">
      <div>
        <p class="kicker">Pleya Share <span class="tag">PREMIUM, AFTER BETA</span></p>
        <h2 class="big" data-split>No server? Your device is one.</h2>
        <p class="lede">
          Share from any device running Pleya. The device holding your files becomes a small media server for your
          other Pleya devices. Shared folders show up as a library next to your servers.
        </p>
        <ol class="share-steps" data-reveal>
          <li>On the host: Settings, Pleya Share, Host, pick folders</li>
          <li>On the other device: Join, scan the QR code</li>
          <li>Stream, and keep separate watch positions per guest</li>
        </ol>
      </div>
      <dl class="routes" data-reveal aria-label="How the two devices find each other">
        {#each routes as [route, how] (route)}
          <div><dt>{route}</dt><dd>{how}</dd></div>
        {/each}
      </dl>
    </div>
    <figure class="share-shot" data-reveal>
      <div class="share-pairing">
        <div class="share-host">
          <p class="share-screen-label">Share from your device</p>
          <div class="share-host-crop">
            <img src={macShare} width="1920" height="1050" loading="lazy"
              alt="Current Pleya Share host panel on Mac, with local-folder sharing, a pairing code and QR code" />
          </div>
        </div>
        <div class="share-receiver">
          <p class="share-screen-label">Watch on another device</p>
          <img class="phone" src={iosHome} width="1206" height="2622" loading="lazy"
            alt="Pleya library on iPhone, with original demo artwork and Liquid Glass navigation" />
        </div>
      </div>
      <figcaption class="cap">Shown here on Mac and iPhone; you can share from any device running Pleya. Scan the QR code on the other device, or type the six digits. The code changes after each pairing.</figcaption>
    </figure>
  </div>
</section>
