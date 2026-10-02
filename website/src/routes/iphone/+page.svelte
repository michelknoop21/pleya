<script lang="ts">
  import Platform from '$lib/components/platform/Platform.svelte';
  import Feature from '$lib/components/platform/Feature.svelte';
  import iosHome from '$lib/assets/home/ios-home.webp';
  import iosDownloads from '$lib/assets/home/ios-downloads.webp';
  import iosPlayer from '$lib/assets/home/ios-player-land.webp';
  import iosMyPleya from '$lib/assets/home/ios-mypleya.webp';
  import iosSearch from '$lib/assets/home/ios-search.webp';
  import macShare from '$lib/assets/home/mac-share.webp';
</script>

<Platform
  title="Pleya on iPhone"
  description="Pleya on iPhone plays your Plex or Jellyfin library, with downloads for offline viewing and the same progress as your Apple TV and Mac."
  path="/iphone"
  kicker="iPhone"
  heading="Your server, in your pocket."
  lede="Browse and play what is on your Plex or Jellyfin server, or download it for when there is no connection."
  shot={{ src: iosHome, w: 603, h: 1311, alt: 'Pleya Home on iPhone', frame: 'phone' }}
>
  <Feature
    kicker="Downloads"
    heading="Three episodes ready before the train leaves."
    shots={[{ src: iosDownloads, w: 603, h: 1311, alt: 'The Downloads tab on iPhone with three finished downloads', frame: 'phone' }]}
  >
    <p class="lede">
      Download a film, a whole show or only the unwatched episodes. A show can carry a rule such as "keep three
      unwatched episodes ready". New episodes then download by themselves.
    </p>
    <ul class="pf-list">
      <li>With no connection, Pleya opens on the Downloads tab and your saved titles play as normal.</li>
      <li>Your position goes back to the server once you are online. If another device got further, the further position wins.</li>
      <li>Download on Wi-Fi only keeps downloads off your mobile data.</li>
    </ul>
  </Feature>

  <Feature
    kicker="Player"
    heading="Double-tap to jump. Swipe the edge for volume."
    flip
    shots={[{ src: iosPlayer, w: 1311, h: 603, alt: 'The Pleya player on iPhone in landscape', frame: 'phone', land: true }]}
  >
    <p class="lede">
      Double-tap the left or right half to jump back or forward. Swipe the left edge for brightness and the right edge
      for volume.
    </p>
    <ul class="pf-list">
      <li>Lock blocks every control against accidental taps.</li>
      <li>Picture in Picture keeps playing in a small window while you use other apps.</li>
      <li>Pleya asks iOS for multichannel audio, so Dolby Atmos and spatial audio work on AirPods.</li>
    </ul>
  </Feature>

  <Feature
    kicker="My Pleya"
    heading="One tab for everything that is yours."
    shots={[{ src: iosMyPleya, w: 603, h: 1311, alt: 'My Pleya on iPhone with the watchlist and downloads', frame: 'phone' }]}
  >
    <p class="lede">My Pleya holds your watchlist, your downloads and your settings, with your profile at the top.</p>
    <p class="lede">
      With more than one profile, Pleya first asks Who's watching? A four-digit PIN locks a profile. It protects the
      profile, not the app.
    </p>
  </Feature>

  <Feature
    kicker="Pleya Share"
    heading="Lock the screen. It keeps serving."
    flip
    shots={[{ src: macShare, w: 1312, h: 724, alt: 'The Pleya Share host screen on a Mac with a pairing code and QR code', frame: 'mac' }]}
  >
    <p class="lede">
      Your iPhone can serve its local folders to your other Pleya devices. Pick the folders, leave the code on screen,
      and the files become a library on the other device.
    </p>
    <p class="lede">
      On iPhone the host keeps running with the screen locked. The picture shows the host screen on a Mac. Pleya Share
      will be part of the paid tier once pricing is announced after the beta.
    </p>
    <p class="links internal"><a href="/#share">How Pleya Share works</a></p>
  </Feature>

  <Feature
    kicker="Search"
    heading="One search across every server."
    shots={[{ src: iosSearch, w: 603, h: 1311, alt: 'Search results for "star" on iPhone', frame: 'phone' }]}
  >
    <p class="lede">Search looks through every connected server at once, on title, cast member or keyword.</p>
  </Feature>
</Platform>
