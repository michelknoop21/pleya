<script lang="ts">
  const routes = [
    ['Same Wi-Fi', 'Direct, over the local network.'],
    ['Wi-Fi Aware', 'A direct link with no router or hotspot, on iOS 26 and most Android phones.'],
    ['Hotspot', 'The addresses in the QR code plus the hotspot gateway.'],
    ['Cable', 'Ethernet adapters or USB tethering, over link-local addressing.'],
    ['Anywhere', 'An end-to-end encrypted relay when both devices are online on different networks.'],
  ];
</script>

<section class="share" id="share">
  <div class="wrap share-grid">
    <div>
      <p class="kicker">Pleya Share <span class="tag">PREMIUM, AFTER BETA</span></p>
      <h2 class="big" data-split>No server? Your phone is one.</h2>
      <p class="lede">
        Pleya Share turns the device holding the files into a small media server for your other Pleya devices. The
        shared folders show up as a library next to your servers.
      </p>
      <ol class="share-steps">
        <li>On the host: Settings, Pleya Share, Host, pick folders</li>
        <li>On the other device: Join, scan the QR code</li>
        <li>Stream, and keep separate watch positions per guest</li>
      </ol>
    </div>
    <dl class="routes" aria-label="How the two devices find each other">
      {#each routes as [route, how] (route)}
        <div><dt>{route}</dt><dd>{how}</dd></div>
      {/each}
    </dl>
  </div>
</section>
