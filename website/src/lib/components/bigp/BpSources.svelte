<script lang="ts">
  import PlexIcon from '~icons/simple-icons/plex';
  import JellyfinIcon from '~icons/simple-icons/jellyfin';
  import EmbyIcon from '~icons/simple-icons/emby';
  import FolderIcon from '~icons/material-symbols-light/folder-outline-rounded';
  import ServerIcon from '~icons/material-symbols-light/home-storage-outline-rounded';

  const sources = [
    { icon: PlexIcon, name: 'Plex' },
    { icon: JellyfinIcon, name: 'Jellyfin' },
    { icon: EmbyIcon, name: 'Emby' },
    { icon: ServerIcon, name: 'Pleya Server' },
    { icon: FolderIcon, name: 'Local folders' },
  ];
</script>

<section class="bp-section works-with" id="sources" aria-labelledby="sources-title">
  <div class="wrap grid">
    <div class="bp-head" data-reveal>
      <p class="eyebrow">Works with</p>
      <h2 id="sources-title" data-split>The libraries you already have.</h2>
      <p class="lede">Big P reads the sources you added to Pleya. One question covers all of them, and the answer says which server a title is on.</p>
    </div>
    <div>
      <ul class="list" data-reveal>
        {#each sources as s (s.name)}
          <li><s.icon aria-hidden="true" />{s.name}</li>
        {/each}
      </ul>
      <dl class="extra" data-reveal>
        <div><dt>Seerr</dt><dd>Adds requests: Big P can look up a title you do not have and ask for it. <a href="/docs/requests">Connect Seerr</a></dd></div>
        <div><dt>Tautulli</dt><dd>Adds watch statistics for Plex, such as who is watching right now. <a href="/docs/tautulli">Connect Tautulli</a></dd></div>
      </dl>
    </div>
  </div>
</section>

<style>
  .grid { display: grid; gap: 3rem; }
  .list { display: grid; font-family: var(--display); font-size: clamp(1.6rem, 3vw, 2.4rem); font-weight: 600; letter-spacing: -0.02em; }
  .list li { display: flex; align-items: center; gap: 1rem; padding-block: 0.7rem; border-bottom: 1px solid var(--hair); }
  .list :global(svg) { flex-shrink: 0; font-size: 0.8em; color: var(--amber); }
  .extra { margin-top: 2rem; display: grid; gap: 1.2rem; }
  .extra div { display: grid; gap: 0.2rem; }
  dt { font-weight: 600; }
  dd { color: var(--muted); font-size: 0.98rem; }
  dd a { color: var(--ink); text-decoration: underline; text-decoration-color: var(--amber); text-underline-offset: 0.3em; white-space: nowrap; }
  @media (min-width: 900px) {
    .grid { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 5rem; align-items: start; }
    .extra div { grid-template-columns: 6rem 1fr; gap: 1rem; }
  }
</style>
