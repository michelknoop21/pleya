<script lang="ts">
  import '../docs/docs.css';
  import TopNav from '$lib/components/TopNav.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import { pageMotion } from '$lib/motion';

  const sections = [
    { id: 'introduction', title: "Introduction" },
    { id: 'your-recommendations-stay-on-your-device', title: "Your Recommendations Stay on Your Device" },
    { id: 'information-we-collect', title: "Information We Collect" },
    { id: 'how-we-use-your-information', title: "How We Use Your Information" },
    { id: 'data-storage-and-security', title: "Data Storage and Security" },
    { id: 'third-party-services', title: "Third-Party Services" },
    { id: 'data-sharing', title: "Data Sharing" },
    { id: 'your-rights-and-choices', title: "Your Rights and Choices" },
    { id: 'children-s-privacy', title: "Children's Privacy" },
    { id: 'changes-to-this-privacy-policy', title: "Changes to This Privacy Policy" },
    { id: 'data-retention', title: "Data Retention" },
    { id: 'international-data-transfers', title: "International Data Transfers" },
    { id: 'legal-compliance', title: "Legal Compliance" },
    { id: 'your-consent', title: "Your Consent" }
  ];

  let active = $state(sections[0].id);

  // Which section is being read, for the index. An observer, not a scroll
  // listener: it costs nothing while nothing crosses the band.
  $effect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) if (entry.isIntersecting) active = entry.target.id;
      },
      { rootMargin: '-20% 0px -65% 0px' }
    );
    document.querySelectorAll('.policy-section').forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  });
</script>

<svelte:head>
  <title>Privacy Policy - Pleya</title>
  <meta name="description" content="Learn how Pleya handles your data when connecting to Plex and Jellyfin. Our privacy policy covers authentication, crash diagnostics, local network information, and data storage practices." />
  <link rel="canonical" href="https://pleya.app/privacy" />

  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content="Privacy Policy - Pleya" />
  <meta property="og:description" content="Learn how Pleya handles your data. Our privacy policy covers authentication, crash diagnostics, local network information, and data storage practices." />
  <meta property="og:url" content="https://pleya.app/privacy" />
  <meta property="og:image" content="https://pleya.app/og/pleya-social.png" />

  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="Privacy Policy - Pleya" />
  <meta name="twitter:description" content="Learn how Pleya handles your data. Our privacy policy covers authentication, crash diagnostics, local network information, and data storage practices." />
  <meta name="twitter:image" content="https://pleya.app/og/pleya-social.png" />
</svelte:head>

<div class="docs privacy" use:pageMotion>
  <TopNav sticky />
  <div class="aura" aria-hidden="true"></div>

  <main class="policy-shell">
    <header class="policy-lede">
      <span class="tag">Legal</span>
      <h1 data-split>Privacy Policy</h1>
      <p class="last-updated">Last Updated: October 12, 2026</p>

      <nav class="index" aria-label="On this page">
        <div class="index-core">
          <p class="index-label">On this page</p>
          <ol>
            {#each sections as section (section.id)}
              <li>
                <a href="#{section.id}" aria-current={active === section.id ? 'true' : undefined}>{section.title}</a>
              </li>
            {/each}
          </ol>
        </div>
      </nav>
    </header>

    <div class="policy-body">
      <section class="policy-section" id="introduction">
        <div class="core" data-reveal>
          <h2>Introduction</h2>
          <p>Pleya ("we", "our", or "the app") is a third-party client for Plex and Jellyfin that allows you to access and stream content from your media server. This privacy policy explains how we handle your information when you use our app.</p>
        </div>
      </section>
      <section class="policy-section" id="your-recommendations-stay-on-your-device">
        <div class="core" data-reveal>
          <h2>Your Recommendations Stay on Your Device</h2>
          <p>Pleya builds personalized recommendations by analyzing your library and viewing activity <strong>entirely on your device</strong>. Your taste profile is computed and stored locally &mdash; it is never uploaded to us, and we do not use it to track or profile you across services. If you use Big P, parts of it (what you watched recently and what you like, such as genres, actors and directors) can go to the AI provider you chose, as described under Data Sharing. This processing powers the "for you" suggestions inside the app and nothing more.</p>
        </div>
      </section>
      <section class="policy-section" id="information-we-collect">
        <div class="core" data-reveal>
          <h2>Information We Collect</h2>

          <h3>Authentication Information</h3>
          <p>When you sign in to Pleya, we collect and process the following information depending on which service you connect:</p>
          <ul>
            <li>Plex: authentication tokens, account username, and server connection information</li>
            <li>Jellyfin: server URL, access token, username, and user ID</li>
          </ul>

          <h3>Crash and Diagnostic Data</h3>
          <p>To help us identify and fix bugs, the app automatically collects:</p>
          <ul>
            <li>Crash reports and error stack traces</li>
            <li>Application Not Responding (ANR) events</li>
            <li>Device model, OS version, and app version</li>
            <li>Diagnostic breadcrumbs (e.g. playback events leading up to a crash)</li>
          </ul>
          <p>This data is sent to our self-hosted error tracking server (bugs.pleya.app). Sensitive information such as authentication tokens and server URLs is automatically stripped before transmission.</p>

          <h3>Local Network Information</h3>
          <p>To connect to your media server on your local network, we may access:</p>
          <ul>
            <li>Local network device discovery information</li>
            <li>IP addresses of media servers on your network</li>
          </ul>

          <h3>Usage Information</h3>
          <p>The app stores locally on your device:</p>
          <ul>
            <li>Your authentication session</li>
            <li>App preferences and settings</li>
            <li>Recently accessed content history</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="how-we-use-your-information">
        <div class="core" data-reveal>
          <h2>How We Use Your Information</h2>
          <p>We use the collected information solely to:</p>
          <ul>
            <li>Authenticate you with your Plex or Jellyfin account</li>
            <li>Connect to and communicate with your media server</li>
            <li>Display your media library and stream content</li>
            <li>Maintain your session and app preferences</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="data-storage-and-security">
        <div class="core" data-reveal>
          <h2>Data Storage and Security</h2>
          <ul>
            <li>Authentication tokens are stored securely on your device using platform-specific secure storage mechanisms</li>
            <li>App preferences are stored locally on your device</li>
            <li>Crash and diagnostic data is sent to our self-hosted error tracking server (bugs.pleya.app) &mdash; no third-party services receive this data</li>
            <li>All other communication is directly between your device and your media server, with Plex's authentication services when signing in with Plex, or with Trakt if you connect your Trakt account</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="third-party-services">
        <div class="core" data-reveal>
          <h2>Third-Party Services</h2>

          <h3>Plex</h3>
          <p>Pleya uses Plex's authentication and media services. When you use this app:</p>
          <ul>
            <li>You authenticate directly with Plex's servers</li>
            <li>Your media streaming occurs between your device and your Plex Media Server</li>
            <li>Plex's own privacy policy applies to their services: <a href="https://www.plex.tv/about/privacy-legal/" target="_blank" rel="noopener noreferrer">plex.tv/about/privacy-legal</a></li>
          </ul>
          <p>We do not control and are not responsible for Plex's data practices.</p>

          <h3>Jellyfin</h3>
          <p>Pleya can connect to your self-hosted Jellyfin server. When you use this app with Jellyfin:</p>
          <ul>
            <li>You authenticate directly with your Jellyfin server using your username and password, or via Quick Connect</li>
            <li>Your media streaming occurs between your device and your Jellyfin server</li>
            <li>No third party (including Pleya) is involved in Jellyfin authentication or playback</li>
          </ul>
          <p>Because Jellyfin is self-hosted, your Jellyfin server's privacy practices are determined by whoever operates it. More information about the Jellyfin project is available at <a href="https://jellyfin.org" target="_blank" rel="noopener noreferrer">jellyfin.org</a>.</p>

          <h3>Trakt (optional)</h3>
          <p>Pleya can connect to your Trakt account. This is off until you sign in with a code at trakt.tv/activate. When you connect:</p>
          <ul>
            <li>Your Trakt access token is stored on your device and is used only to talk to Trakt</li>
            <li>After you connect, Pleya asks once whether it may send your watching to Trakt. Only if you allow it, Pleya sends play, pause and stop events and "watched" marks (identifiers such as IMDb or TMDB IDs, the season and episode number, how far you are, and when). If Trakt cannot be reached, Pleya keeps the pending watched marks on your device and tries again later. You can switch each off under Settings &gt; Trakt. If you sync your settings through iCloud, your answer syncs to your other devices too. A rating you give in Pleya is sent to Trakt as well</li>
            <li>Pleya reads your Trakt watched history and watchlist so it can leave out titles you have already seen and show your watchlist next to your libraries. The history is used on your device and is not saved to disk. If you ask Big P about your watchlist, up to 30 titles from it are included in the request to the AI provider you chose</li>
            <li>Trakt is not available on children's profiles</li>
            <li>You can disconnect under Settings &gt; Trakt, which revokes the token at Trakt when Trakt can be reached</li>
          </ul>
          <p>Trakt's own privacy policy applies: <a href="https://trakt.tv/privacy" target="_blank" rel="noopener noreferrer">trakt.tv/privacy</a>. We do not control Trakt's data practices.</p>

          <h3>Litterbox (Discord Rich Presence)</h3>
          <p>When Discord Rich Presence is enabled, media artwork may be temporarily uploaded to:</p>
          <ul>
            <li>Litterbox (litterbox.catbox.moe) &mdash; a temporary file hosting service</li>
          </ul>
          <p>These uploads are necessary because Discord requires publicly accessible image URLs for Rich Presence artwork. Uploaded images automatically expire after 1 hour. This feature is opt-in and disabled by default.</p>
        </div>
      </section>
      <section class="policy-section" id="data-sharing">
        <div class="core" data-reveal>
          <h2>Data Sharing</h2>
          <p>We do not:</p>
          <ul>
            <li>Sell your personal information</li>
            <li>Share your information with third parties for marketing purposes</li>
            <li>Transmit your data to our own servers (except crash/diagnostic reports as described above)</li>
            <li>Track your viewing habits outside of local app functionality, except what you choose to send to Trakt as described above</li>
          </ul>
          <p>Depending on what you use, your data is shared with:</p>
          <ul>
            <li>Plex services for authentication and media server communication, when signing in with Plex (as required for the app to function)</li>
            <li>Your self-hosted Jellyfin server, when signing in with Jellyfin (as required for the app to function)</li>
            <li>Trakt, if you connect your Trakt account and allow Pleya to send your watching</li>
            <li>The AI provider you set up for Big P, if you use it: your questions, earlier messages in the conversation, your profile name, what Big P remembers about you, and the results it looks up to answer them (for example what you watched recently, what you like, titles from your libraries and, when you ask about it, your Trakt watchlist)</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="your-rights-and-choices">
        <div class="core" data-reveal>
          <h2>Your Rights and Choices</h2>
          <p>You can:</p>
          <ul>
            <li>Sign out at any time to remove your authentication session from the device</li>
            <li>Uninstall the app to remove all locally stored data</li>
            <li>Manage your Plex account directly through Plex's services, or your Jellyfin account through your Jellyfin server</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="children-s-privacy">
        <div class="core" data-reveal>
          <h2>Children's Privacy</h2>
          <p>Pleya does not knowingly collect personal information from children under 13. The app relies on authentication with Plex or Jellyfin servers, and users must comply with the terms of service and age requirements of whichever service they connect to.</p>
        </div>
      </section>
      <section class="policy-section" id="changes-to-this-privacy-policy">
        <div class="core" data-reveal>
          <h2>Changes to This Privacy Policy</h2>
          <p>We may update this privacy policy from time to time. We will notify users of any material changes by updating the "Last Updated" date at the top of this policy.</p>
        </div>
      </section>
      <section class="policy-section" id="data-retention">
        <div class="core" data-reveal>
          <h2>Data Retention</h2>
          <ul>
            <li>Authentication tokens are retained on your device until you sign out or uninstall the app</li>
            <li>Local preferences and settings are retained until you uninstall the app</li>
            <li>Crash and diagnostic reports are retained on our self-hosted server and automatically pruned based on relevance</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="international-data-transfers">
        <div class="core" data-reveal>
          <h2>International Data Transfers</h2>
          <p>As we do not operate backend servers, there are no international data transfers from our side. Any data transfers occur directly between your device and either Plex's services (subject to Plex's privacy policy) or your Jellyfin server (governed by whoever operates it).</p>
        </div>
      </section>
      <section class="policy-section" id="legal-compliance">
        <div class="core" data-reveal>
          <h2>Legal Compliance</h2>
          <p>This app complies with:</p>
          <ul>
            <li>General Data Protection Regulation (GDPR)</li>
            <li>California Consumer Privacy Act (CCPA)</li>
            <li>Children's Online Privacy Protection Act (COPPA)</li>
            <li>Other applicable privacy laws</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="your-consent">
        <div class="core" data-reveal>
          <h2>Your Consent</h2>
          <p>By using Pleya, you consent to this privacy policy and the processing of your information as described herein.</p>
        </div>
      </section>
    </div>
  </main>

  <Footer />
</div>

<style>
  /* One easing for everything that moves: a heavy start that settles. */
  .privacy {
    --ease: cubic-bezier(0.32, 0.72, 0, 1);
    --bezel: 0.375rem;
    --radius: 2rem;
    position: relative;
    isolation: isolate;
  }

  /* Brand light behind the page: fixed, so it never repaints with the scroll. */
  .aura {
    position: fixed;
    inset: 0;
    z-index: -1;
    pointer-events: none;
    background:
      radial-gradient(58rem 38rem at 8% -8%, rgba(229, 20, 15, 0.17), transparent 62%),
      radial-gradient(46rem 34rem at 96% 6%, rgba(255, 176, 32, 0.08), transparent 60%);
  }

  .policy-shell {
    max-width: 78rem;
    margin-inline: auto;
    padding: 3rem 1rem 5rem;
    display: grid;
    gap: 2.5rem;
  }

  .tag {
    display: inline-flex;
    align-items: center;
    padding: 0.3rem 0.8rem;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.05);
    color: var(--color-accent-2);
    font-size: 0.625rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    text-transform: uppercase;
  }

  .policy-lede h1 {
    margin-top: 1.25rem;
    font-size: clamp(3rem, 6.2vw, 5.25rem);
    font-weight: 800;
    line-height: 0.92;
    letter-spacing: -0.045em;
  }

  .last-updated {
    margin-top: 1.25rem;
    color: var(--color-text-faint);
    font-size: 0.875rem;
    font-variant-numeric: tabular-nums;
  }

  /* The index sits in a tray: an outer shell with a hairline, and an inner
     plate with its own highlight and a concentric, smaller radius. */
  .index {
    display: none;
    margin-top: 2.5rem;
    padding: var(--bezel);
    border-radius: 1.75rem;
    border: 1px solid rgba(255, 255, 255, 0.09);
    background: rgba(255, 255, 255, 0.03);
  }

  .index-core {
    padding: 1.25rem 1.25rem 1rem;
    border-radius: calc(1.75rem - var(--bezel));
    background: #0b0b0c;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1);
  }

  .index-label {
    margin-bottom: 0.75rem;
    color: var(--color-text-faint);
    font-size: 0.625rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    text-transform: uppercase;
  }

  /* On a low window the list scrolls inside its plate, so the last entries
     stay reachable while the column is pinned. */
  .index ol {
    margin: 0;
    padding: 0;
    list-style: none;
    counter-reset: entry;
    max-height: max(9rem, calc(100dvh - 30rem));
    overflow-y: auto;
    overscroll-behavior: contain;
  }

  .index a {
    display: flex;
    align-items: baseline;
    gap: 0.75rem;
    padding: 0.3rem 0;
    color: var(--color-text-muted);
    font-size: 0.875rem;
    line-height: 1.35;
    transition:
      color 500ms var(--ease),
      transform 500ms var(--ease);
  }

  .index a::before {
    counter-increment: entry;
    content: counter(entry, decimal-leading-zero);
    flex: none;
    color: var(--color-text-faint);
    font-size: 0.6875rem;
    font-variant-numeric: tabular-nums;
    transition: color 500ms var(--ease);
  }

  .index a:hover,
  .index a[aria-current] {
    color: var(--color-text);
    transform: translateX(0.25rem);
  }

  .index a[aria-current]::before {
    color: var(--color-accent-2);
  }

  .policy-body {
    counter-reset: section;
    min-width: 0;
  }

  /* Each section is a plate in a tray, like the index. No blur here: these
     scroll, and a blurred surface that scrolls repaints every frame. */
  .policy-section {
    padding: var(--bezel);
    border-radius: 1.5rem;
    border: 1px solid rgba(255, 255, 255, 0.08);
    background: rgba(255, 255, 255, 0.03);
    scroll-margin-top: 6rem;
  }

  .policy-section + .policy-section {
    margin-top: 1.25rem;
  }

  .core {
    counter-increment: section;
    padding: 1.5rem 1.25rem 1.25rem;
    border-radius: calc(1.5rem - var(--bezel));
    background: #0b0b0c;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.09);
    color: var(--color-text-muted);
    line-height: 1.75;
  }

  .core::before {
    content: counter(section, decimal-leading-zero);
    display: block;
    margin-bottom: 0.75rem;
    color: var(--color-accent-2);
    font-size: 0.6875rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    font-variant-numeric: tabular-nums;
  }

  .core h2 {
    margin-bottom: 1rem;
    color: var(--color-text);
    font-size: clamp(1.375rem, 2.4vw, 1.75rem);
    font-weight: 700;
    line-height: 1.15;
    letter-spacing: -0.02em;
  }

  .core h3 {
    margin-top: 2rem;
    margin-bottom: 0.5rem;
    color: var(--color-text);
    font-size: 1.0625rem;
    font-weight: 600;
    line-height: 1.3;
  }

  .core :is(p, ul) {
    max-width: 62ch;
    margin-bottom: 1rem;
  }

  .core > :last-child {
    margin-bottom: 0;
  }

  .core ul {
    padding-left: 1.25rem;
    list-style: disc;
  }

  .core li {
    margin-bottom: 0.375rem;
  }

  .core li::marker {
    color: var(--color-text-faint);
  }

  .core strong {
    color: var(--color-text);
    font-weight: 600;
  }

  .core a {
    color: var(--color-accent-2);
    text-decoration: underline;
    text-decoration-color: rgba(255, 176, 32, 0.4);
    text-underline-offset: 0.2em;
    transition: text-decoration-color 500ms var(--ease);
  }

  .core a:hover {
    text-decoration-color: currentColor;
  }

  @media (min-width: 48rem) {
    .policy-shell {
      padding: 5rem 2rem 8rem;
    }

    .policy-section {
      border-radius: var(--radius);
    }

    .core {
      padding: 2.5rem 2.75rem 2.25rem;
      border-radius: calc(var(--radius) - var(--bezel));
    }
  }

  /* Editorial split: the title and the index stay put while the plates scroll. */
  @media (min-width: 64rem) {
    .policy-shell {
      grid-template-columns: minmax(0, 23rem) minmax(0, 1fr);
      gap: 5rem;
      padding-block: 7rem 10rem;
    }

    .policy-lede {
      position: sticky;
      top: 7rem;
      align-self: start;
    }

    .index {
      display: block;
    }
  }
</style>
