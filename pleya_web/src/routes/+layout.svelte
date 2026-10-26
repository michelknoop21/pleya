<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { dev } from '$app/env';

  import '../styles/tokens.css';
  import '../styles/base.css';

  import TopNav from '#lib/components/TopNav.svelte';
  import MobileHeader from '#lib/components/MobileHeader.svelte';
  import TabBar from '#lib/components/TabBar.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import UnreachableState from '#lib/components/UnreachableState.svelte';
  import { activeItemId, navItems } from '#lib/components/navItems.js';
  import { adminBackHref, isAdminPath } from '#lib/admin/sections.js';
  import { isPlayerPath } from '#lib/player/route.js';
  import { session } from '#lib/stores/session.svelte.js';
  import { theme } from '#lib/stores/theme.svelte.js';
  import { viewport } from '#lib/stores/viewport.svelte.js';
  import { initLocale, t } from '#lib/i18n/index.js';

  // Vóór de eerste markup: `t()` is niet reactief, dus de taal moet vaststaan
  // voordat een kind rendert. In `onMount` kwam dit te laat en bleef de pagina
  // Engels staan.
  initLocale();

  let { children }: { children: Snippet } = $props();

  // Onbereikbaar: de schil tekent wat de kijker de laatste keer zag
  // (lastContact). Zonder record blijft alleen Mijn Pleya over, want er is dan
  // niets bekend over bladeren of bibliotheken.
  const unreachable = $derived(session.phase === 'unreachable');
  const navLibraries = $derived(
    unreachable ? (session.lastContact?.libraries ?? []) : session.libraries
  );
  const navCapabilities = $derived(
    unreachable
      ? session.lastContact
        ? { browse: session.lastContact.browse }
        : null
      : session.capabilities
  );
  const items = $derived(navItems(navCapabilities, navLibraries));
  const activeId = $derived(activeItemId(items, page.url.pathname, navLibraries));
  // Zoeken vraagt de server; zolang die niet antwoordt, staat de actie er niet.
  const showSearch = $derived(!unreachable && session.capabilities?.search === true);
  const searchActive = $derived(page.url.pathname.startsWith('/search'));
  // De Beheer-pil alleen voor eigenaar of beheerder (S10.1); in beheer zelf
  // wordt de mobiele kop een terugkop naar de index of naar Pleya.
  const inAdmin = $derived(isAdminPath(page.url.pathname));
  const adminBack = $derived.by(() => {
    const href = adminBackHref(page.url.pathname);
    return href && session.canAdminister ? { href, title: t('admin.title') } : null;
  });
  // De primitievengalerij heeft geen server nodig en hoort niet achter de
  // sessiepoort; buiten `vite dev` is `dev` onwaar en valt deze tak weg.
  const isDevGallery = $derived(dev && page.url.pathname.startsWith('/dev/'));
  const isAuthRoute = $derived(
    page.url.pathname === '/login' || page.url.pathname === '/setup'
  );
  // De speler (mockup 50) vult het hele venster, zonder topnav of tabbalk.
  const isPlayer = $derived(isPlayerPath(page.url.pathname));

  onMount(() => {
    const stopTheme = theme.start();
    const stopViewport = viewport.start();
    void session.ensureStarted();
    return () => {
      stopTheme();
      stopViewport();
    };
  });

  /**
   * Waar de gebruiker hoort te zijn, gegeven de toestand van de sessie.
   *
   * `null` betekent: hier is niets mis mee, blijf staan.
   */
  const expectedPath = $derived.by(() => {
    if (isDevGallery) return null;
    if (session.phase === 'setup') return '/setup';
    if (session.phase === 'signed-out') return '/login';
    if (session.phase === 'ready' && isAuthRoute) return '/';
    return null;
  });

  /**
   * Of de huidige route bij de toestand past.
   *
   * Dit is meer dan een cosmetische controle. `goto` is asynchroon, dus tussen
   * "de sessie is er niet" en "de browser staat op /login" zit een frame
   * waarin de oude pagina nog gemonteerd is. Rendert die pagina in dat frame,
   * dan doet hij zijn aanvraag alsnog, krijgt een 401, en dat telt als een
   * verloren sessie terwijl er nooit een was — waarna een server die nog
   * opgezet moet worden een inlogscherm laat zien. Niets renderen tot de route
   * klopt is de enige plek waar dat sluitend te maken is.
   */
  const routeMatchesPhase = $derived(expectedPath === null);

  // De schil stuurt zelf naar setup of inloggen. Dat is geen routebewaking op
  // de server: de bundel is statisch en iedereen kan elk pad opvragen. Wat
  // beschermt is de API, die zonder geldig token niets geeft.
  $effect(() => {
    const target = expectedPath;
    if (target !== null && page.url.pathname !== target) {
      void goto(target, { replace: true });
    }
  });

  $effect(() => {
    document.documentElement.dataset['theme'] = theme.palette;
  });
</script>

<svelte:head>
  <title>{t('app.name')}</title>
</svelte:head>

<a class="skip-link" href="#main">{t('nav.skipToContent')}</a>

{#if isDevGallery}
  <main id="main" class="dev-shell">
    {@render children()}
  </main>
{:else if session.phase === 'starting'}
  <SkeletonPage variant="compact" />
{:else if session.phase === 'setup' || session.phase === 'signed-out'}
  <main id="main" class="auth-shell">
    {#if page.url.pathname === expectedPath}
      {@render children()}
    {:else}
      <SkeletonPage variant="compact" />
    {/if}
  </main>
{:else if !routeMatchesPhase}
  <SkeletonPage variant="compact" />
{:else if isPlayer && !unreachable}
  <main id="main" class="player-shell">
    {@render children()}
  </main>
{:else}
  <div class="shell" class:shell--wide={viewport.wide}>
    {#if viewport.wide}
      <TopNav
        {items}
        {activeId}
        {showSearch}
        {searchActive}
        showAdmin={session.canAdminister}
        adminActive={inAdmin}
      />
    {:else}
      <MobileHeader
        {showSearch}
        {searchActive}
        showAdmin={session.canAdminister}
        back={adminBack}
      />
    {/if}

    <main id="main" class="shell__main">
      {#if unreachable}
        <!-- Een navigatieklik verandert de URL maar rendert de route niet:
             die zou meteen zelf aanvragen doen. Komt de server terug, dan
             landt de gebruiker op de route waar hij intussen heen klikte. -->
        <UnreachableState
          name={session.lastContact?.name ?? page.url.host}
          host={page.url.host}
          lastContactAt={session.lastContact?.at ?? null}
          signedIn={session.client.tokens.refreshToken !== null}
          onRetry={() => session.start()}
        />
      {:else}
        {@render children()}
      {/if}
    </main>

    {#if !viewport.wide}
      <TabBar {items} {activeId} />
    {/if}
  </div>
{/if}

<style>
  .shell {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
  }

  .shell__main {
    flex: 1 1 auto;
    min-width: 0;
    padding-bottom: var(--space-3);
  }

  /* Ruimte voor de tabbalk, zodat de laatste rij niet eronder valt. */
  .shell:not(.shell--wide) .shell__main {
    padding-bottom: calc(
      var(--bottom-bar-height) + env(safe-area-inset-bottom, 0px) + var(--space-2)
    );
  }

  .dev-shell,
  .player-shell {
    min-height: 100dvh;
  }

  /* Inloggen (12) loopt tot de rand en setup (40) centreert een eigen kolom;
     elke route bepaalt zijn opbouw zelf, de schil geeft alleen de hoogte. */
  .auth-shell {
    min-height: 100dvh;
  }
</style>
