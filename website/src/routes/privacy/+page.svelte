<script lang="ts">
  import '../docs/docs.css';
  import TopNav from '$lib/components/TopNav.svelte';
  import Footer from '$lib/components/Footer.svelte';

  const sections = [
    { id: 'introduction', title: "Introduction" },
    { id: 'your-recommendations-stay-on-your-device', title: "Your Recommendations Stay on Your Device" },
    { id: 'big-p-the-assistant', title: "Big P, the Assistant" },
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
  let root: HTMLElement | undefined = $state();
  let list: HTMLElement | undefined = $state();
  let end: HTMLElement | undefined = $state();

  // Which section is being read. Observers, not a scroll listener.
  //
  // A section counts while it crosses a band near the top of the window; of
  // several, the first in the document wins, so a short section is not skipped
  // for the next. A section the reader asked for (a click in the index, a link
  // with a hash) is marked at once and stays marked until they scroll on their
  // own or it leaves the window: near the end of the page a short section can
  // never reach the band. At the real end of the page it is the last section,
  // which on a tall window never reaches the band either.
  $effect(() => {
    const page = root;
    const tail = end;
    if (!page || !tail) return;
    const plates = [...page.querySelectorAll<HTMLElement>('.policy-section')];
    const known = new Set(plates.map((plate) => plate.id));
    const inBand = new Set<string>();
    const onScreen = new Set<string>();
    let atEnd = false;
    let chosen: string | undefined;
    let chosenAt = 0;
    // What the index shows, kept beside the state so this effect never reads it.
    let shown = sections[0].id;

    const settle = () => {
      if (chosen && !onScreen.has(chosen)) chosen = undefined;
      shown =
        chosen ??
        (atEnd ? sections[sections.length - 1].id : (plates.find((plate) => inBand.has(plate.id))?.id ?? shown));
      active = shown;
    };
    const choose = (id: string) => {
      if (!known.has(id)) return;
      // Shown before the jump, so the plate does not move after landing.
      document.getElementById(id)?.classList.add('in');
      onScreen.add(id);
      chosen = id;
      chosenAt = performance.now();
      settle();
    };
    const release = () => {
      if (!chosen) return;
      chosen = undefined;
      settle();
    };

    // The band starts just under where a jump lands: under the pill bar on a
    // narrow window, near the top on a wide one.
    const bandTop = window.matchMedia('(min-width: 64rem)').matches ? 56 : 96;
    const band = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) inBand.add(entry.target.id);
          else inBand.delete(entry.target.id);
        }
        settle();
      },
      { rootMargin: `-${bandTop}px 0px -60% 0px` }
    );
    const screen = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) onScreen.add(entry.target.id);
        else onScreen.delete(entry.target.id);
      }
      settle();
    });
    // The marker sits under the footer: it shows only at the real end of the page.
    const bottom = new IntersectionObserver(
      (entries) => {
        atEnd = entries[entries.length - 1].isIntersecting;
        settle();
      },
      { rootMargin: '0px 0px 8px 0px' }
    );
    plates.forEach((plate) => {
      band.observe(plate);
      screen.observe(plate);
    });
    bottom.observe(tail);

    const fromHash = () => choose(decodeURIComponent(location.hash.slice(1)));
    const onClick = (event: MouseEvent) => {
      // A click that opens the link elsewhere does not move this page.
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = (event.target as Element | null)?.closest?.('a[href^="#"]');
      if (link) choose(decodeURIComponent(link.getAttribute('href')!.slice(1)));
    };
    const onKey = (event: KeyboardEvent) => {
      if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(event.key)) release();
    };
    // A scroll that ends some time after the jump is the reader's own, also
    // when it came from the scrollbar and sent no wheel, touch or key.
    const onScrollEnd = () => {
      if (performance.now() - chosenAt > 700) release();
    };
    if (location.hash) {
      fromHash();
      // The browser jumped before the fonts were in, and the text above has
      // since changed height: land once more, unless the reader moved on.
      const target = chosen;
      document.fonts?.ready.then(() => {
        if (target && chosen === target) document.getElementById(target)?.scrollIntoView();
      });
    }
    window.addEventListener('hashchange', fromHash);
    window.addEventListener('scrollend', onScrollEnd);
    page.addEventListener('click', onClick);
    window.addEventListener('wheel', release, { passive: true });
    window.addEventListener('touchmove', release, { passive: true });
    window.addEventListener('keydown', onKey);

    return () => {
      band.disconnect();
      screen.disconnect();
      bottom.disconnect();
      window.removeEventListener('hashchange', fromHash);
      window.removeEventListener('scrollend', onScrollEnd);
      page.removeEventListener('click', onClick);
      window.removeEventListener('wheel', release);
      window.removeEventListener('touchmove', release);
      window.removeEventListener('keydown', onKey);
    };
  });

  // Keep the current entry in view when the index scrolls: a list in its plate
  // on a wide window, a row of pills on a narrow one.
  $effect(() => {
    const box = list;
    const item = box?.querySelector<HTMLElement>(`a[href="#${active}"]`)?.parentElement;
    if (!box || !item) return;
    const top = item.offsetTop - box.offsetTop;
    if (top < box.scrollTop) box.scrollTop = top;
    else if (top + item.offsetHeight > box.scrollTop + box.clientHeight)
      box.scrollTop = top + item.offsetHeight - box.clientHeight;
    const left = item.offsetLeft - box.offsetLeft;
    if (left < box.scrollLeft) box.scrollLeft = left - 16;
    else if (left + item.offsetWidth > box.scrollLeft + box.clientWidth)
      box.scrollLeft = left + item.offsetWidth - box.clientWidth + 16;
  });

  // Plates rise into place as they arrive. A plate that has not arrived is
  // dimmed, never invisible: this is a legal text, and it has to stay readable
  // even if the reveal never fires. The section itself does not move (only the
  // plate inside it), so a jump to its anchor lands where it should. What is
  // already on screen is marked first, so nothing visible flashes. Without
  // script or with reduced motion nothing is dimmed.
  $effect(() => {
    const page = root;
    if (!page || !window.matchMedia('(prefers-reduced-motion: no-preference)').matches) return;
    const plates = [...page.querySelectorAll<HTMLElement>('.policy-section')];
    for (const plate of plates) if (plate.getBoundingClientRect().top < window.innerHeight) plate.classList.add('in');
    page.classList.add('motion');
    const arrive = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add('in');
          arrive.unobserve(entry.target);
        }
      },
      { rootMargin: '0px 0px -4% 0px' }
    );
    plates.forEach((plate) => arrive.observe(plate));
    // A link reached with Tab inside a plate that has not arrived yet shows it.
    const onFocus = (event: FocusEvent) => (event.target as Element | null)?.closest?.('.policy-section')?.classList.add('in');
    page.addEventListener('focusin', onFocus);
    return () => {
      arrive.disconnect();
      page.removeEventListener('focusin', onFocus);
      page.classList.remove('motion');
    };
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

<div class="docs privacy" bind:this={root}>
  <TopNav />
  <div class="aura" aria-hidden="true"></div>

  <main class="policy-shell">
    <header class="policy-lede">
      <span class="tag">Legal</span>
      <h1>Privacy Policy</h1>
      <p class="last-updated">Last Updated: October 12, 2026</p>

      <nav class="index" aria-label="On this page">
        <div class="index-core">
          <p class="index-label">On this page</p>
          <ol bind:this={list}>
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
        <div class="core">
          <h2>Introduction</h2>
          <p>Pleya ("we", "our", or "the app") is a third-party client for Plex and Jellyfin that allows you to access and stream content from your media server. This privacy policy explains how we handle your information when you use our app.</p>
        </div>
      </section>
      <section class="policy-section" id="your-recommendations-stay-on-your-device">
        <div class="core">
          <h2>Your Recommendations Stay on Your Device</h2>
          <p>Pleya builds personalized recommendations by analyzing your library and viewing activity <strong>entirely on your device</strong>. Your taste profile is computed and stored locally &mdash; it is never uploaded to us, and we do not use it to track or profile you across services. If you use Big P, parts of it (what you watched recently and what you like, such as genres, actors and directors) can go to the AI provider you chose, as described under Big P, the Assistant. This processing powers the "for you" suggestions inside the app and nothing more.</p>
        </div>
      </section>
      <section class="policy-section" id="big-p-the-assistant">
        <div class="core">
          <h2>Big P, the Assistant</h2>
          <p>Big P is the assistant inside Pleya. It is optional: it does nothing until you set it up under Settings &gt; Big P and choose where its language model runs.</p>

          <div class="well">
            <h3>Your AI provider</h3>
            <ul>
              <li>You choose the provider: your own Ollama server, Ollama Cloud (ollama.com) or OpenRouter (openrouter.ai), with your own API key. Pleya has no AI service of its own: your conversations go to the provider you chose, not to us</li>
              <li>When you ask something, Pleya sends that provider: your question, earlier messages in the same conversation, your profile name, the app language, a few things Big P remembers about you that fit the question, and the results it looks up to answer you. Those results can include titles from your libraries, the names of your servers and libraries, what you watched recently and what you like, viewing figures from your media server or Tautulli with the names of the accounts on your server and what they are watching, request status from Seerr, and your Trakt watchlist when you ask about it</li>
              <li>The provider's own privacy policy applies to what it does with that. With your own Ollama server the conversation goes only to that server; online title information and web search are separate and described below</li>
              <li>Your provider settings and keys (the API key, an optional web search key and your TMDB key) are stored in iCloud Keychain on iPhone, iPad and Apple TV, so they sync between your Apple devices, and on the device elsewhere</li>
              <li>Diagnostic logs you choose to send us from Settings can contain fragments of a question when debug logging is on</li>
            </ul>
          </div>

          <div class="well">
            <h3>Conversations and memory</h3>
            <ul>
              <li>A conversation is kept in memory while you use it. It is not saved to disk</li>
              <li>Big P stores something in its memory when you ask it to, or after you confirm a suggestion it makes. What it remembers is stored on your device, per profile, and is not synced. You can see and remove it in the memory screen under Settings &gt; Big P, or ask Big P what it remembers and to forget it</li>
              <li>When you open that memory screen, Big P asks your provider to write a summary of what it remembers. For that summary the remembered facts are sent to the provider</li>
            </ul>
          </div>

          <div class="well">
            <h3>Online title information</h3>
            <ul>
              <li>For facts about a title (age rating, genres, runtime, cast, score, where it streams) Big P first uses your own media server and Seerr</li>
              <li>With "Add online information" on, which is the default, it also asks TMDB (with your own key, if you entered one), Trakt, TVmaze and Wikidata. These receive the title's public identifier (IMDb, TMDB or TVDB) or, when Big P searches for a title, its name, together with the app language. They do not receive your account or what you watched</li>
              <li>With "Search the web" on, Big P also looks up a title it cannot identify from your description: on Wikipedia and Wikidata, and through the web search of Ollama (ollama.com) or OpenRouter. The description you gave is sent there. This is on by default with Ollama Cloud and OpenRouter. With your own Ollama server it is off by default, and the web search itself then needs a separate ollama.com key</li>
              <li>You can switch both off under Settings &gt; Big P</li>
            </ul>
          </div>

          <div class="well">
            <h3>Children's profiles</h3>
            <ul>
              <li>On a children's profile Big P cannot read watching history, viewing figures, request status, the Trakt watchlist or its memory</li>
              <li>To leave out titles that do not fit, the age of the youngest child you entered is included in what goes to the provider</li>
            </ul>
          </div>
        </div>
      </section>
      <section class="policy-section" id="information-we-collect">
        <div class="core">
          <h2>Information We Collect</h2>

          <div class="well">
            <h3>Authentication Information</h3>
            <p>When you sign in to Pleya, we collect and process the following information depending on which service you connect:</p>
            <ul>
              <li>Plex: authentication tokens, account username, and server connection information</li>
              <li>Jellyfin: server URL, access token, username, and user ID</li>
            </ul>
          </div>
          <div class="well">
            <h3>Crash and Diagnostic Data</h3>
            <p>Crash reporting is switched on per build. The current App Store and TestFlight builds have it switched off and send no crash reports. In a build where it is on, the app automatically collects, to help us identify and fix bugs:</p>
            <ul>
              <li>Crash reports and error stack traces</li>
              <li>Application Not Responding (ANR) events</li>
              <li>Device model, OS version, and app version</li>
              <li>Diagnostic breadcrumbs (e.g. playback events leading up to a crash)</li>
            </ul>
            <p>This data is sent to our self-hosted error tracking server (bugs.pleya.app). Sensitive information such as authentication tokens and server URLs is automatically stripped before transmission.</p>
          </div>
          <div class="well">
            <h3>Local Network Information</h3>
            <p>To connect to your media server on your local network, we may access:</p>
            <ul>
              <li>Local network device discovery information</li>
              <li>IP addresses of media servers on your network</li>
            </ul>
          </div>
          <div class="well">
            <h3>Usage Information</h3>
            <p>The app stores locally on your device:</p>
            <ul>
              <li>Your authentication session</li>
              <li>App preferences and settings</li>
              <li>Recently accessed content history</li>
            </ul>
          </div>
        </div>
      </section>
      <section class="policy-section" id="how-we-use-your-information">
        <div class="core">
          <h2>How We Use Your Information</h2>
          <p>We use the collected information only to:</p>
          <ul>
            <li>Authenticate you with your Plex or Jellyfin account</li>
            <li>Connect to and communicate with your media server</li>
            <li>Display your media library and stream content</li>
            <li>Maintain your session and app preferences</li>
            <li>Answer your questions in Big P, if you set it up, as described under Big P, the Assistant</li>
            <li>Keep the optional services you connect working, such as Trakt, Seerr, Tautulli, Watch Together and Discord Rich Presence</li>
            <li>Find and fix bugs, from crash reports and from the logs you choose to send us</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="data-storage-and-security">
        <div class="core">
          <h2>Data Storage and Security</h2>
          <ul>
            <li>Sign-in tokens for your media server (Plex, Jellyfin), Seerr and Tautulli are stored on your device in encrypted form (AES-256-GCM). The encryption key is kept in the app's own storage on the same device, so this protects against casual reading of the app's data, not against someone with full access to your device</li>
            <li>On iPhone, iPad and Apple TV, your Big P provider settings and keys are stored in iCloud Keychain, and the tokens for Trakt and the other trackers in the keychain of that device, which does not sync. On other platforms these are stored in the same encrypted form as above</li>
            <li>App preferences are stored locally on your device</li>
            <li>Crash and diagnostic data is sent to our self-hosted error tracking server (bugs.pleya.app) &mdash; no third-party service stores this data. It reaches our server through Cloudflare</li>
            <li>Our relay server (ice.pleya.app) is used only when you use one of these features: logs you send us from Settings (kept for 3 days; a sent log gets a short ID, and whoever has that ID can read it until it expires), Watch Together (what is playing, with its title and position, and the display names of the participants; a room expires after 24 hours at most), artwork for Discord Rich Presence (removed after 3 hours), and signing in to MyAnimeList or AniList (the sign-in passes through the relay; your tokens are not logged or stored there). Signing in to Simkl ends on a page the relay serves. The relay's own server log records your IP address with each upload; that log is rotated by size, not by date</li>
            <li>All other communication goes directly from your device to the service involved: your media server, Plex's authentication services when signing in with Plex, and the optional services you connect or switch on, such as Trakt and other trackers, Seerr, Tautulli, your Big P provider and the online sources it uses. None of that passes through our servers</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="third-party-services">
        <div class="core">
          <h2>Third-Party Services</h2>

          <div class="well">
            <h3>Plex</h3>
            <p>Pleya uses Plex's authentication and media services. When you use this app:</p>
            <ul>
              <li>You authenticate directly with Plex's servers</li>
              <li>Your media streaming occurs between your device and your Plex Media Server</li>
              <li>Plex's own privacy policy applies to their services: <a href="https://www.plex.tv/about/privacy-legal/" target="_blank" rel="noopener noreferrer">plex.tv/about/privacy-legal</a></li>
            </ul>
            <p>We do not control and are not responsible for Plex's data practices.</p>
          </div>
          <div class="well">
            <h3>Jellyfin</h3>
            <p>Pleya can connect to your self-hosted Jellyfin server. When you use this app with Jellyfin:</p>
            <ul>
              <li>You authenticate directly with your Jellyfin server using your username and password, or via Quick Connect</li>
              <li>Your media streaming occurs between your device and your Jellyfin server</li>
              <li>No third party (including Pleya) is involved in Jellyfin authentication or playback</li>
            </ul>
            <p>Because Jellyfin is self-hosted, your Jellyfin server's privacy practices are determined by whoever operates it. More information about the Jellyfin project is available at <a href="https://jellyfin.org" target="_blank" rel="noopener noreferrer">jellyfin.org</a>.</p>
          </div>
          <div class="well">
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
          </div>
          <div class="well">
            <h3>MyAnimeList, AniList and Simkl (optional)</h3>
            <p>Pleya can connect to these trackers. Each is off until you sign in, and not every build offers all three. When you connect one:</p>
            <ul>
              <li>Your access token is stored on your device and is used only to talk to that tracker. Signing in to MyAnimeList or AniList passes through our relay, as described under Data Storage and Security</li>
              <li>From then on Pleya keeps that tracker's list in step with what you watch or mark in Pleya: the title's identifier, the season and episode you reached and whether you completed it. That covers titles you play to the end, titles you mark as watched by hand (a whole season or series sends every episode), and watching done offline or in an external player once it syncs. Marking something unwatched removes it from the tracker's list again. This starts when you connect; you can switch it off per tracker under Settings &gt; Trackers</li>
              <li>A rating you give or clear in Pleya is sent as well. To show them, Pleya reads your username and your existing ratings from the tracker</li>
              <li>To match anime to MyAnimeList and AniList, Pleya downloads two public mapping lists through jsDelivr and checks them for updates weekly. jsDelivr sees your IP address; the request does not say what you watch</li>
              <li>You can disconnect under Settings &gt; Trackers, which removes the token from your device</li>
            </ul>
            <p>Their own privacy policies apply: <a href="https://myanimelist.net/about/privacy_policy" target="_blank" rel="noopener noreferrer">myanimelist.net/about/privacy_policy</a>, <a href="https://anilist.co/terms" target="_blank" rel="noopener noreferrer">anilist.co/terms</a> and <a href="https://simkl.com" target="_blank" rel="noopener noreferrer">simkl.com</a>. We do not control their data practices.</p>
          </div>
          <div class="well">
            <h3>Discord Rich Presence</h3>
            <p>When Discord Rich Presence is enabled, media artwork may be temporarily uploaded to:</p>
            <ul>
              <li>Our relay server (ice.pleya.app)</li>
            </ul>
            <p>These uploads are necessary because Discord requires publicly accessible image URLs for Rich Presence artwork. Uploaded images are removed after 3 hours. Pleya also passes what you are playing (the title, for an episode the season, episode number and episode title, for a film the year and studio, and how far along you are) to the Discord app on your computer, which shows it in your Discord status. This feature exists on desktop only, is opt-in and is disabled by default.</p>
          </div>
        </div>
      </section>
      <section class="policy-section" id="data-sharing">
        <div class="core">
          <h2>Data Sharing</h2>
          <p>We do not:</p>
          <ul>
            <li>Sell your personal information</li>
            <li>Share your information with third parties for marketing purposes</li>
            <li>Transmit your data to our own servers (except crash/diagnostic reports and the relay uses described under Data Storage and Security)</li>
            <li>Track your viewing habits outside of local app functionality, except what you choose to send to Trakt or another tracker as described above</li>
          </ul>
          <p>Depending on what you use, your data is shared with:</p>
          <ul>
            <li>Plex services for authentication and media server communication, when signing in with Plex (as required for the app to function)</li>
            <li>Your self-hosted Jellyfin server, when signing in with Jellyfin (as required for the app to function)</li>
            <li>Trakt, if you connect your Trakt account and allow Pleya to send your watching</li>
            <li>MyAnimeList, AniList or Simkl, if you connect one: what you watch or mark as watched and the ratings you give</li>
            <li>Discord, when Discord Rich Presence is on: the title you are playing and how far along you are</li>
            <li>The AI provider you set up for Big P, as described under Big P, the Assistant</li>
            <li>Your Seerr server (Jellyseerr or Overseerr), if you connect it: your searches and the requests you make. Pleya signs in to it with your Plex account token, or with the email and password or the API key you enter; those are kept encrypted on your device to sign in again. This is a server you or someone you know runs</li>
            <li>Your Tautulli server, if you connect it: Pleya reads viewing history from it, with the API key you entered</li>
            <li>TMDB, Trakt, TVmaze, Wikidata and Wikipedia, when Big P looks up title information online: a title's public identifier, its name or a search phrase, never your account</li>
            <li>The web search of Ollama or OpenRouter, when "Search the web" is on: the description of the title you are looking for</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="your-rights-and-choices">
        <div class="core">
          <h2>Your Rights and Choices</h2>
          <p>You can:</p>
          <ul>
            <li>Sign out at any time to remove your authentication session from the device</li>
            <li>Uninstall the app to remove the data it stores on your iPhone, iPad or Apple TV. Items in the keychain are not removed by uninstalling: disconnect your trackers on each profile and turn off Big P under Settings &gt; Big P first if you want those gone. On Windows, Linux and Mac, uninstalling can leave the app's settings files behind, including the encrypted tokens; disconnect or sign out first there as well. Turning off Big P removes its settings and keys from iCloud Keychain, so from your other Apple devices as well</li>
            <li>Manage your Plex account directly through Plex's services, or your Jellyfin account through your Jellyfin server</li>
            <li>See and remove what Big P remembers under Settings &gt; Big P, and switch off online information and web search there</li>
            <li>Disconnect Trakt under Settings &gt; Trakt, which revokes its token at Trakt when Trakt can be reached</li>
            <li>Disconnect MyAnimeList, AniList or Simkl under Settings &gt; Trackers, which removes the token from your device</li>
            <li>Disconnect Seerr or Tautulli in Settings, which removes the stored sign-in from your device. Viewing history already imported from Tautulli stays on your device but is no longer used</li>
            <li>Ask us to delete a log you sent before it expires, or ask what we hold about you, at <a href="mailto:beta@pleya.app">beta@pleya.app</a></li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="children-s-privacy">
        <div class="core">
          <h2>Children's Privacy</h2>
          <p>Pleya does not knowingly collect personal information from children under 13. The app relies on authentication with Plex or Jellyfin servers, and users must comply with the terms of service and age requirements of whichever service they connect to.</p>
        </div>
      </section>
      <section class="policy-section" id="changes-to-this-privacy-policy">
        <div class="core">
          <h2>Changes to This Privacy Policy</h2>
          <p>We may update this privacy policy from time to time. We will notify users of any material changes by updating the "Last Updated" date at the top of this policy.</p>
        </div>
      </section>
      <section class="policy-section" id="data-retention">
        <div class="core">
          <h2>Data Retention</h2>
          <ul>
            <li>Authentication tokens are retained on your device until you sign out or uninstall the app</li>
            <li>Local preferences and settings are retained until you uninstall the app</li>
            <li>Crash and diagnostic reports are retained on our self-hosted server and automatically pruned based on relevance</li>
            <li>On our relay: logs you send us are kept for 3 days, a Watch Together room for 24 hours at most and Discord artwork for 3 hours. The relay's server log, which includes IP addresses, is rotated by size</li>
            <li>Tokens for Trakt and other trackers are retained on your device until you disconnect the tracker. On iPhone, iPad and Apple TV they are in the keychain of the device, which uninstalling does not empty; a token left there is not read by a later install</li>
            <li>Your Big P provider settings and keys are retained until you turn off Big P. On iPhone, iPad and Apple TV they are in iCloud Keychain and stay there after uninstalling, so a later install finds them again</li>
          </ul>
        </div>
      </section>
      <section class="policy-section" id="international-data-transfers">
        <div class="core">
          <h2>International Data Transfers</h2>
          <p>We run two servers of our own: an error tracking server (bugs.pleya.app) and a relay (ice.pleya.app), both described under Data Storage and Security. They are hosted in the Netherlands and are reached through Cloudflare, which passes the traffic on to them.</p>
          <p>Everything else goes directly from your device to the service you use, and where that data is processed depends on that service: Plex (subject to Plex's privacy policy), your own Jellyfin, Seerr or Tautulli server (governed by whoever operates it), Trakt and the other trackers, Discord, and for Big P the provider you chose and the online sources it uses. Some of these, such as Ollama Cloud, OpenRouter, Trakt, Discord and TMDB, are based in the United States. If you use them, your data is processed outside the European Union under their privacy policies.</p>
        </div>
      </section>
      <section class="policy-section" id="legal-compliance">
        <div class="core">
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
        <div class="core">
          <h2>Your Consent</h2>
          <p>By using Pleya, you consent to this privacy policy and the processing of your information as described herein.</p>
        </div>
      </section>
    </div>
  </main>

  <Footer />
  <div class="page-end" bind:this={end} aria-hidden="true"></div>
</div>

<style>
  /* One easing for everything that moves: a heavy start that settles. */
  .privacy {
    --ease: cubic-bezier(0.32, 0.72, 0, 1);
    --bezel: 0.375rem;
    --radius: 2rem;
    --plate: #0b0b0c;
    --hairline: rgba(255, 255, 255, 0.09);
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

  /* The navigation floats over the top of the page, so the shell starts below it. */
  .policy-shell {
    max-width: 78rem;
    margin-inline: auto;
    padding: 7rem 1rem 5rem;
    display: grid;
    grid-template-columns: minmax(0, 1fr);
  }

  /* Narrow window: the title block dissolves into the page grid, so the index
     can stay pinned under the top edge for the whole length of the policy. */
  .policy-lede {
    display: contents;
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

  .tag {
    justify-self: start;
  }

  .policy-lede h1 {
    margin-top: 1.25rem;
    font-size: clamp(3rem, 9vw, 5.25rem);
    font-weight: 800;
    line-height: 0.92;
    letter-spacing: -0.045em;
  }

  .last-updated {
    margin-top: 1.25rem;
    color: var(--color-text-muted);
    font-size: 0.875rem;
    font-variant-numeric: tabular-nums;
  }

  /* ---------- index ---------- */

  /* Narrow window: a row of pills that scrolls sideways, pinned under the top
     edge while the policy is read. Blur is allowed here: the bar itself does
     not scroll. */
  .index {
    position: sticky;
    top: 0;
    z-index: 4;
    margin: 1.5rem -1rem 1.25rem;
    padding: 0.5rem 0;
    background: rgba(0, 0, 0, 0.72);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    backdrop-filter: blur(14px) saturate(140%);
  }

  .index-label {
    display: none;
  }

  .index ol {
    display: flex;
    gap: 0.5rem;
    margin: 0;
    padding: 0.25rem 1rem;
    list-style: none;
    counter-reset: entry;
    overflow: auto hidden;
    scrollbar-width: none;
    /* The row fades out at its right edge: there is more to the side. */
    -webkit-mask-image: linear-gradient(to right, #000 calc(100% - 2.5rem), transparent);
    mask-image: linear-gradient(to right, #000 calc(100% - 2.5rem), transparent);
  }

  .index ol::-webkit-scrollbar {
    display: none;
  }

  .index li {
    flex: none;
  }

  .index li:last-child {
    padding-right: 2rem;
  }

  .index a {
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.625rem;
    min-height: 2.75rem;
    padding: 0 1rem;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    background: rgba(255, 255, 255, 0.04);
    color: var(--color-text-muted);
    font-size: 0.875rem;
    line-height: 1.35;
    white-space: nowrap;
    transition:
      color 500ms var(--ease),
      background-color 500ms var(--ease),
      border-color 500ms var(--ease);
  }

  .index a::before {
    counter-increment: entry;
    content: counter(entry, decimal-leading-zero);
    /* Decoration: the second value is its empty spoken alternative. */
    content: counter(entry, decimal-leading-zero) / '';
    flex: none;
    color: var(--color-text-faint);
    font-size: 0.6875rem;
    font-variant-numeric: tabular-nums;
    transition: color 500ms var(--ease);
  }

  .index a:hover,
  .index a[aria-current] {
    color: var(--color-text);
  }

  .index a[aria-current] {
    border-color: rgba(255, 176, 32, 0.45);
    background: rgba(255, 176, 32, 0.08);
  }

  .index a[aria-current]::before {
    color: var(--color-accent-2);
  }

  .index a:active {
    transform: scale(0.98);
  }

  /* The ring sits inside the row: the list clips what reaches past its edge. */
  .index a:focus-visible {
    outline-offset: -2px;
    box-shadow: none;
    border-radius: 999px;
  }

  /* ---------- plates ---------- */

  .policy-body {
    counter-reset: section;
    min-width: 0;
  }

  /* Each section is a plate in a tray: an outer shell with a hairline, and an
     inner plate with its own highlight and a concentric, smaller radius. No
     blur here: these scroll, and a blurred surface that scrolls repaints every frame. */
  .policy-section {
    padding: var(--bezel);
    border-radius: 1.5rem;
    border: 1px solid var(--hairline);
    background: rgba(255, 255, 255, 0.03);
    /* Clear of the pinned pill bar. */
    scroll-margin-top: 4.75rem;
  }

  .policy-section + .policy-section {
    margin-top: 1.25rem;
  }

  .core {
    counter-increment: section;
    position: relative;
    padding: 1.5rem 1.25rem 1.25rem;
    border-radius: calc(1.5rem - var(--bezel));
    background: var(--plate);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.09);
    color: var(--color-text-muted);
    line-height: 1.75;
  }

  /* The section number as an outlined numeral: a drawn figure, not a label. */
  .core::before {
    content: counter(section, decimal-leading-zero);
    content: counter(section, decimal-leading-zero) / '';
    display: block;
    margin-bottom: 0.5rem;
    font-family: var(--font-display);
    font-size: 2.75rem;
    font-weight: 800;
    line-height: 1;
    letter-spacing: -0.04em;
    font-variant-numeric: tabular-nums;
    color: transparent;
    -webkit-text-stroke: 1px rgba(255, 176, 32, 0.55);
  }

  .core h2 {
    margin-bottom: 1rem;
    color: var(--color-text);
    font-size: clamp(1.5rem, 2.6vw, 2rem);
    font-weight: 700;
    line-height: 1.12;
    letter-spacing: -0.025em;
  }

  /* A subsection sits one level down, in a well cut into the plate. */
  .well {
    margin-top: 0.75rem;
    padding: 1.25rem 1.125rem 1rem;
    border-radius: 1.125rem;
    border: 1px solid rgba(255, 255, 255, 0.07);
    background: rgba(255, 255, 255, 0.025);
    box-shadow: inset 0 -1px 0 rgba(255, 255, 255, 0.04);
  }

  .core h3 {
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

  .core > :last-child,
  .well > :last-child {
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

  .page-end {
    height: 1px;
  }

  /* ---------- arrival ---------- */

  /* The title block rises once on load (pure CSS, no flash). A plate brightens
     and rises the last stretch as it arrives; until then it is dimmed but
     readable. Neither runs with reduced motion, and the plates not without script. */
  @media (prefers-reduced-motion: no-preference) {
    .policy-lede > * {
      animation: rise 900ms var(--ease) both;
    }
    .policy-lede > :nth-child(2) {
      animation-delay: 70ms;
    }
    .policy-lede > :nth-child(3) {
      animation-delay: 140ms;
    }
    .policy-lede > :nth-child(4) {
      animation-delay: 210ms;
    }

    .privacy:global(.motion) .policy-section {
      opacity: 0.5;
      transition: opacity 900ms var(--ease);
    }
    .privacy:global(.motion) .policy-section .core {
      transform: translateY(2rem);
      transition: transform 900ms var(--ease);
    }
    .privacy:global(.motion) .policy-section:global(.in) {
      opacity: 1;
    }
    .privacy:global(.motion) .policy-section:global(.in) .core {
      transform: none;
    }
  }

  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(1rem);
    }
  }

  /* ---------- wider windows ---------- */

  @media (min-width: 48rem) {
    .policy-shell {
      padding: 9rem 2rem 8rem;
    }

    .policy-section {
      border-radius: var(--radius);
    }

    .core {
      padding: 2.5rem 2.75rem 2.25rem;
      border-radius: calc(var(--radius) - var(--bezel));
    }

    /* The numeral moves to the corner and grows; the heading keeps clear of it. */
    .core::before {
      position: absolute;
      top: 2.125rem;
      right: 2.5rem;
      margin: 0;
      font-size: clamp(3rem, 4.6vw, 3.75rem);
      -webkit-text-stroke-color: rgba(255, 176, 32, 0.34);
    }

    .core h2 {
      max-width: calc(100% - 7rem);
    }

    .well {
      padding: 1.5rem 1.5rem 1.25rem;
    }
  }

  /* Editorial split: the title and the index stay put while the plates scroll,
     and the index becomes a list in its own tray. */
  @media (min-width: 64rem) {
    .policy-shell {
      grid-template-columns: minmax(0, 23rem) minmax(0, 1fr);
      gap: 5rem;
      padding-block: 7.5rem 10rem;
    }

    .policy-lede {
      display: block;
      min-width: 0;
    }

    .policy-lede h1 {
      font-size: clamp(3rem, 6.2vw, 5.25rem);
    }

    .policy-section {
      scroll-margin-top: 1.5rem;
    }

    .index {
      position: static;
      z-index: auto;
      margin: 2rem 0 0;
      -webkit-backdrop-filter: none;
      backdrop-filter: none;
      padding: var(--bezel);
      border-radius: 1.75rem;
      border: 1px solid var(--hairline);
      background: rgba(255, 255, 255, 0.03);
    }

    .index-core {
      padding: 1.25rem 1.25rem 1rem;
      border-radius: calc(1.75rem - var(--bezel));
      background: var(--plate);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1);
    }

    .index-label {
      display: block;
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
      display: block;
      margin: 0;
      padding: 0;
      max-height: max(9rem, calc(100dvh - 26rem));
      overflow: hidden auto;
      -webkit-mask-image: none;
      mask-image: none;
    }

    .index li:last-child {
      padding-right: 0;
    }

    .index a {
      min-height: 0;
      padding: 0.24rem 0 0.24rem 0.875rem;
      border: 0;
      border-radius: 0.5rem;
      background: none;
      white-space: normal;
      align-items: baseline;
      gap: 0.75rem;
    }

    .index a[aria-current] {
      background: none;
    }

    /* The mark of the section being read: a short bar that grows from its middle. */
    .index a::after {
      content: '';
      position: absolute;
      left: 0;
      top: 0.45rem;
      bottom: 0.45rem;
      width: 2px;
      border-radius: 2px;
      background: var(--color-accent-2);
      transform: scaleY(0);
      transition: transform 500ms var(--ease);
    }

    .index a[aria-current]::after {
      transform: scaleY(1);
    }

    .index a:active {
      transform: none;
    }

    .index a:focus-visible {
      border-radius: 0.5rem;
    }
  }

  /* Pinned only where the column fits on the window. */
  @media (min-width: 64rem) and (min-height: 40rem) {
    .policy-lede {
      position: sticky;
      top: 2.5rem;
      align-self: start;
    }
  }

  /* ---------- paper ---------- */

  /* Last, so it wins from the wide-window rules on landscape paper. The dark
     theme has no place on paper: white ground, ink colours, plain outlined
     blocks, and only the policy itself (no navigation, index or footer). */
  @page {
    margin: 16mm;
  }

  @media print {
    .privacy,
    :global(html),
    :global(body) {
      background: #fff !important;
      color: #000 !important;
    }
    .aura,
    .index,
    .page-end,
    .privacy :global(.topnav),
    .privacy :global(.site-footer) {
      display: none !important;
    }
    .policy-shell {
      display: block !important;
      padding: 0 !important;
    }
    .policy-lede {
      display: block !important;
      position: static !important;
      margin-bottom: 2rem;
    }
    .policy-lede > * {
      animation: none !important;
    }
    .policy-lede h1,
    .core h2,
    .core h3,
    .core strong,
    .core a {
      color: #000;
    }
    .core,
    .last-updated {
      color: #222;
    }
    .tag {
      color: #555;
      border-color: #bbb;
      background: none;
    }
    .core::before {
      position: static;
      margin: 0 0 0.25rem;
      font-size: 1.25rem;
      -webkit-text-stroke-color: #888;
    }
    .core h2 {
      max-width: none;
    }
    .policy-section {
      border-color: #ccc;
      background: none;
      opacity: 1 !important;
      transition: none !important;
    }
    .core {
      transform: none !important;
      transition: none !important;
    }
    .core,
    .well {
      background: none;
      box-shadow: none;
    }
    .well {
      border-color: #ddd;
    }
    .core :is(p, ul) {
      max-width: none;
    }
    .core a {
      text-decoration-color: #000;
    }
    .core {
      padding: 1rem 1.25rem;
    }
    .core :is(h2, h3) {
      break-after: avoid;
    }
    .core li::marker {
      color: #555;
    }
  }
</style>
