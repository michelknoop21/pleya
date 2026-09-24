<script lang="ts">
  import Platform from '$lib/components/platform/Platform.svelte';
  import Feature from '$lib/components/platform/Feature.svelte';
  import tvHome from '$lib/assets/home/tv-home.webp';
  import tvNav from '$lib/assets/home/tv-nav.webp';
  import tvPlayer from '$lib/assets/home/tv-player.webp';
  import tvSearch from '$lib/assets/home/tv-search.webp';
  import tvDetail from '$lib/assets/home/tv-detail.webp';
  import tvMyPleya from '$lib/assets/home/tv-mypleya.webp';
</script>

<Platform
  title="Pleya on Apple TV"
  description="Pleya on Apple TV: every screen reachable with the Siri Remote, direct play, and the same library as your iPhone and Mac."
  path="/apple-tv"
  kicker="Apple TV"
  heading="Every screen, one D-pad away."
  lede="The focus ring shows where you are. Everything on the screen is reachable with the remote's D-pad."
  shot={{ src: tvHome, w: 1920, h: 1080, alt: 'Pleya Home on Apple TV', frame: 'tv' }}
>
  <Feature
    kicker="Siri Remote"
    heading="Long-press for the quick menu."
    shots={[{ src: tvNav, w: 1920, h: 1080, alt: 'The top bar on Apple TV with the focus ring on Series', frame: 'tv' }]}
  >
    <p class="lede">
      Swipe the touchpad or click the ring to move the focus one step. Select opens what is focused. Menu goes back.
    </p>
    <ul class="pf-list">
      <li>Long-press select on a poster to open its quick menu.</li>
      <li>Play/pause plays and pauses without opening the controls.</li>
      <li>Search, Home, Series, Movies and My Pleya sit in the bar at the top.</li>
    </ul>
  </Feature>

  <Feature
    kicker="Seeking and skipping"
    heading="Scrub on a still frame, then jump."
    flip
    shots={[{ src: tvPlayer, w: 1920, h: 1080, alt: 'The Pleya player on Apple TV with the controls and timeline open', frame: 'tv' }]}
  >
    <p class="lede">
      Press select on the timeline and playback pauses on a preview frame. Left and right move the preview. Select
      jumps there, and back cancels without moving.
    </p>
    <ul class="pf-list">
      <li>Keep swiping and the seek speeds up from 1.5x to 10x. It resets when you change direction.</li>
      <li>Up jumps straight to Skip intro or Skip credits while the button is on screen.</li>
      <li>Automatic intro skipping applies to episodes only. In a film, a chapter called "Intro" is usually part of the film.</li>
    </ul>
  </Feature>

  <Feature
    kicker="Search"
    heading="Say the title, or type it on your iPhone."
    shots={[{ src: tvSearch, w: 1920, h: 1080, alt: 'The tvOS system keyboard in Pleya search with "star" typed', frame: 'tv' }]}
  >
    <p class="lede">
      Press select on the search field and the tvOS system keyboard opens, with what you already typed still in it.
    </p>
    <ul class="pf-list">
      <li>The Siri Remote's microphone dictates into the same keyboard. Results update while you speak.</li>
      <li>A nearby iPhone can type into it too.</li>
      <li>If the keyboard does not appear, Pleya switches to its own on-screen keyboard for the D-pad.</li>
    </ul>
  </Feature>

  <Feature
    kicker="Picture and sound"
    heading="Passthrough, with a fallback that says so."
    flip
    shots={[{ src: tvDetail, w: 1920, h: 1080, alt: 'A film detail page on Apple TV showing 4K, Dolby Vision and 5.1 audio', frame: 'tv' }]}
  >
    <p class="lede">
      Passthrough sends the compressed stream to your receiver. If the receiver refuses it, Pleya falls back to PCM
      within a second and tells you. It remembers that route for the next episode.
    </p>
    <ul class="pf-list">
      <li>Auto decodes on the Apple TV and sends PCM. It never bitstreams.</li>
      <li>PCM always decodes on the Apple TV.</li>
      <li>Pleya asks tvOS for multichannel audio, which lets Dolby Atmos reach your receiver.</li>
    </ul>
    <p class="lede">
      A title can sit on your server in more than one quality, for example a 4K file and a 1080p one. Version &amp;
      quality in the player switches between them.
    </p>
  </Feature>

  <Feature
    kicker="My Pleya"
    heading="Set it up on the Mac. The TV follows."
    shots={[{ src: tvMyPleya, w: 1920, h: 1080, alt: 'My Pleya on Apple TV with the profile, servers online and the watchlist', frame: 'tv' }]}
  >
    <p class="lede">
      My Pleya shows your profile, which servers are online, and your watchlist, collections and playlists.
    </p>
    <p class="lede">
      Settings sync through iCloud. A change made on your Mac reaches the Apple TV while both are open. Settings tied to
      one device, such as volume and HDR, stay on that device.
    </p>
    <p class="links internal"><a href="/mac">Pleya on Mac</a></p>
  </Feature>
</Platform>
