<section class="integrations" id="integrations" aria-labelledby="integrations-title">
  <div class="wrap">
    <p class="kicker">Connected to your server</p>
    <div class="integration-heading">
      <h2 class="integration-title" id="integrations-title" data-split>More to discover.<br />More insight.</h2>
      <p class="lede integration-intro">Bring requests and Plex activity into Pleya with the services you already run.</p>
    </div>

    <div class="integration-grid" data-reveal>
      <article class="integration">
        <p class="integration-label">Discovery &amp; requests</p>
        <h3>Seerr</h3>
        <p class="integration-summary">Find your next film or series, even before it is in your library. Request it and follow its progress without leaving Pleya.</p>
        <ul class="integration-features">
          <li><strong>Explore beyond your library.</strong> Browse trending and popular titles, search, and filter by genre.</li>
          <li><strong>Request a film or a season.</strong> Pick the seasons you want. Approval follows the permissions on your requests server.</li>
          <li><strong>Know when it is ready.</strong> Follow pending, processing, partially available and available titles. Your requests stay together in one list.</li>
        </ul>
        <p class="integration-note">Connect in Settings → Integrations → Requests with a Plex login, local account or administrator API key. Seerr brings together Jellyseerr and Overseerr; Pleya also supports those existing servers.</p>
        <a class="integration-link" href="/docs/requests">Connect Seerr and make a request <span aria-hidden="true">↗</span></a>
      </article>

      <article class="integration">
        <p class="integration-label">Plex activity &amp; history</p>
        <h3>Tautulli</h3>
        <p class="integration-summary">For the person who runs the Plex server: see what is playing now, who watched a title and how your collection is being used.</p>
        <ul class="integration-features">
          <li><strong>See live activity.</strong> Open the active streams from the desktop toolbar or the Apple TV sidebar while someone is watching.</li>
          <li><strong>Put a title in context.</strong> Detail pages show viewers, play counts and recent watch statistics from your connected Tautulli server.</li>
          <li><strong>Give recommendations a head start.</strong> Optionally use the history Tautulli recorded before Pleya. Each profile gets only its own history, processed on this device.</li>
        </ul>
        <p class="integration-note">Plex only. Connect in Settings → Integrations → Tautulli with a device token or API key. Credentials stay on this device, outside iCloud sync and settings export.</p>
        <a class="integration-link" href="/docs/tautulli">Connect Tautulli and use your history <span aria-hidden="true">↗</span></a>
      </article>
    </div>
  </div>
</section>

<style>
  .integrations { padding-block: clamp(3rem, 6vw, 6rem); }
  .integration-title { margin-top: .8rem; font-family: var(--display); font-size: clamp(2.6rem, 4.5vw, 4rem); line-height: 1; }
  .integration-intro { margin-top: 1.5rem; }
  .integration-grid { display: grid; gap: 2.5rem; margin-top: 2.5rem; }
  .integration { min-width: 0; padding-top: 1.5rem; border-top: 1px solid #ffffff24; }
  .integration-label { color: var(--amber); font-size: .72rem; line-height: 1.5; letter-spacing: .12em; text-transform: uppercase; }
  .integration h3 { margin-top: .5rem; font-family: var(--display); font-size: clamp(2rem, 3vw, 3rem); line-height: 1.1; }
  .integration-summary { margin-top: 1rem; font-size: 1.125rem; line-height: 1.6; color: var(--ink); }
  .integration-features { display: grid; gap: 1.1rem; margin-top: 1.5rem; color: var(--muted); line-height: 1.6; }
  .integration-features strong { color: var(--ink); font-weight: 600; }
  .integration-note { margin-top: 1.5rem; color: var(--muted); font-size: .875rem; line-height: 1.65; }
  .integration-link { display: inline-flex; align-items: center; gap: .7rem; min-height: 44px; margin-top: 1rem; color: var(--ink); font-size: .9375rem; text-decoration: underline; text-underline-offset: .25em; }
  .integration-link:hover { color: var(--amber); }
  .integration-link:focus-visible { outline: 2px solid var(--amber); outline-offset: 4px; border-radius: 4px; }
  @media (min-width: 900px) {
    .integration-heading, .integration-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: clamp(2.5rem, 5vw, 5rem); }
    .integration-heading { align-items: end; }
    .integration-intro { margin-top: 0; }
  }
</style>
