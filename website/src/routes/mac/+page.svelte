<script lang="ts">
  import Platform from '$lib/components/platform/Platform.svelte';
  import Feature from '$lib/components/platform/Feature.svelte';
  import macHome from '$lib/assets/home/mac-home.webp';
  import macShare from '$lib/assets/home/mac-share.webp';
</script>

<Platform
  title="Pleya on Mac"
  description="Pleya on Mac plays your Plex or Jellyfin library in a window you control with a pointer and a keyboard."
  path="/mac"
  kicker="Mac"
  heading="Your library, with a pointer and a keyboard."
  lede="The same library and watch progress as on your iPhone and Apple TV, in a window on your desk."
  shot={{ src: macHome, w: 1312, h: 822, alt: 'Pleya Discover on a Mac', frame: 'mac' }}
>
  <Feature kicker="Keyboard" heading="Cmd+F goes straight to Search." shots={[]}>
    <p class="lede">
      On a Mac, Cmd+F opens Search directly. It looks through every connected server at once, on title, cast member or
      keyword.
    </p>
    <ul class="pf-list">
      <li>Keyboard shortcuts sit under Advanced in Settings. You can rebind every one of them.</li>
      <li>In the player, move the mouse or press a key to bring up the controls. They fade again on their own.</li>
    </ul>
  </Feature>

  <Feature kicker="Player" heading="Keep it playing in a small window." shots={[]}>
    <p class="lede">Picture in Picture keeps the video playing in a small window while you use other apps on your Mac.</p>
    <ul class="pf-list">
      <li>The gear icon in the player sets the playback speed, faster or slower.</li>
      <li>A sleep timer stops after a set time, or at the end of the video.</li>
      <li>Audio sync and subtitle sync shift the sound or the subtitles when they drift.</li>
      <li>Settings has an mpv configuration, for people who know what they want from mpv.</li>
    </ul>
  </Feature>

  <Feature
    kicker="Pleya Share"
    heading="Share the folders on your Mac."
    shots={[{ src: macShare, w: 1312, h: 724, alt: 'The Pleya Share host screen on a Mac with a pairing code and QR code', frame: 'mac' }]}
  >
    <p class="lede">
      Your Mac can serve its local folders to your other Pleya devices. Pick the folders and keep the host screen open.
      The files become a library on the other device.
    </p>
    <p class="lede">
      The pairing code changes after each successful pairing. Pleya Share will be part of the paid tier once pricing is
      announced after the beta.
    </p>
    <p class="links internal"><a href="/#share">How Pleya Share works</a></p>
  </Feature>

  <Feature kicker="Details" heading="Switch from 4K to 1080p while it plays." shots={[]}>
    <p class="lede">
      A title can exist on your server in more than one quality, for example a 4K file and a 1080p one. Pleya picks one
      to start with. Version &amp; quality in the player switches during playback.
    </p>
    <p class="lede">
      With a Tautulli server connected, a detail page also shows who has seen the title, how often it was played and how
      much of it was watched in the past month. On a Mac, the toolbar leads to what is streaming from your server right
      now. That part is Plex only, for the person who runs the server.
    </p>
  </Feature>

  <Feature kicker="Settings" heading="Change it on the Mac. The Apple TV follows." shots={[]}>
    <p class="lede">
      Settings sync through iCloud, so a new Apple device starts configured. A change made on your Mac reaches the Apple
      TV while both are open.
    </p>
    <ul class="pf-list">
      <li>A device that was asleep checks for changes when you come back to it.</li>
      <li>One line under the iCloud switch says what the sync is doing, including when something was last sent.</li>
      <li>Volume, download folder, hardware decoding and HDR stay on the device they describe.</li>
      <li>Pleya Share pairing secrets stay out of iCloud and out of export.</li>
      <li>Export settings and Import settings move your configuration to another device.</li>
    </ul>
  </Feature>
</Platform>
