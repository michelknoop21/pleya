<script lang="ts">
  import PlexIcon from '~icons/simple-icons/plex';
  import JellyfinIcon from '~icons/simple-icons/jellyfin';
  import tvServers from '$lib/assets/home/mac-home-315.webp';
  import iosServers from '$lib/assets/home/ios-home-315-glass.webp';
</script>

<section class="unified" id="unified">
  <div class="wrap unified-grid">
    <div>
      <p class="kicker">One library</p>
      <h2 class="big" data-split>Every server. One&nbsp;library.</h2>
      <ul class="sources" aria-label="Sources Pleya merges">
        <li data-source><PlexIcon aria-hidden="true" />Plex</li>
        <li data-source><JellyfinIcon aria-hidden="true" />Jellyfin</li>
        <li data-source>And the next server you add</li>
        <li class="into" data-source>merged on Home and in search</li>
      </ul>
      <p class="lede">
        Keep several servers connected at the same time, Plex and Jellyfin side by side. Home and search treat them as
        one library, so you stop remembering which box a film lives on.
      </p>
    </div>
    <figure class="unified-shots">
      <img class="tv" src={tvServers} width="2624" height="1644" loading="lazy" alt="Pleya on Mac showing films from two original demo collections together" />
      <img class="phone" src={iosServers} width="603" height="1311" loading="lazy" alt="Pleya Home on iPhone with the original demo library" />
      <figcaption class="cap">
        Two demo collections, together in the real Pleya app. Original artwork created for this preview.
      </figcaption>
    </figure>
  </div>
</section>
