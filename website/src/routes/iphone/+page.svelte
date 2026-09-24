<script lang="ts">
  import Platform from '$lib/components/platform/Platform.svelte';
  import iosHome from '$lib/assets/home/ios-home.webp';
</script>

<Platform
  title="Pleya on iPhone"
  description="Pleya on iPhone plays your Plex or Jellyfin library, with downloads for offline viewing and the same progress as your Apple TV and Mac."
  path="/iphone"
  kicker="iPhone"
  heading="Your server, in your pocket."
  lede="Browse and play what is on your Plex or Jellyfin server, or download it for when there is no connection."
  shot={{ src: iosHome, w: 603, h: 1311, alt: 'Pleya Home on iPhone', frame: 'phone' }}
/>
