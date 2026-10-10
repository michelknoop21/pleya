<!--
  De index van de galerij: een kolom links vanaf 900, daaronder een strook
  chips die bovenaan blijft staan. Gewone ankers, dus springen werkt ook
  zonder script; een scrollmeting markeert alleen welke sectie nu in
  beeld is (aria-current), zodat je bij het scrollen weet waar je bent.
-->
<script lang="ts">
  import { SECTIONS } from './sections';

  let current = $state(SECTIONS[0]?.id ?? '');
  let list = $state<HTMLUListElement>();

  // Huidig is de laatste sectie waarvan de kop boven een lijn op een kwart
  // van het venster staat. Een scrollmeting in plaats van een
  // IntersectionObserver: die gaf bij een anker de vorige sectie, omdat haar
  // onderrand nog een halve pixel in beeld hing.
  $effect(() => {
    let frame = 0;
    const measure = () => {
      frame = 0;
      const line = innerHeight * 0.25;
      let found = SECTIONS[0]?.id ?? '';
      for (const s of SECTIONS) {
        const el = document.getElementById(s.id);
        if (el && el.getBoundingClientRect().top <= line) found = s.id;
      }
      current = found;
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(measure);
    };
    measure();
    addEventListener('scroll', schedule, { passive: true });
    addEventListener('resize', schedule);
    return () => {
      removeEventListener('scroll', schedule);
      removeEventListener('resize', schedule);
      cancelAnimationFrame(frame);
    };
  });

  // Onder 900 is de index een strook die horizontaal scrolt; de huidige chip
  // schuift mee in beeld. 'nearest' laat de pagina zelf staan.
  $effect(() => {
    const link = list?.querySelector(`[href="#${current}"]`);
    link?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  });
</script>

<nav class="gi" aria-label="Secties">
  <p class="gi__label">Primitieven</p>
  <ul class="gi__list" bind:this={list}>
    {#each SECTIONS as section (section.id)}
      <li>
        <a
          class="gi__link"
          href="#{section.id}"
          aria-current={current === section.id ? 'true' : undefined}
          onclick={() => (current = section.id)}>{section.title}</a
        >
      </li>
    {/each}
  </ul>
</nav>

<style>
  .gi {
    position: sticky;
    top: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
    height: 100dvh;
    padding: 22px 16px;
    overflow-y: auto;
    border-right: 1px solid var(--hairline);
  }

  .gi__label {
    margin: 0;
    padding: 8px 10px 6px;
    font-size: var(--text-caps-size);
    font-weight: 600;
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: var(--ink-4);
  }

  .gi__list {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  /* Specimen v2, zijbalk: 40 hoog, 10 rond, de huidige op een lichte waas. */
  .gi__link {
    display: flex;
    align-items: center;
    min-height: 40px;
    padding: 0 10px;
    border-radius: 10px;
    font-size: 14px;
    font-weight: 500;
    color: var(--ink-2);
    text-decoration: none;
    transition: background-color var(--dur-fast) var(--ease);
  }

  .gi__link:hover {
    background: var(--row-hover);
    color: var(--ink);
  }

  /* --fill is 8 procent inkt, de waas van het specimen (.075) in elk thema. */
  .gi__link[aria-current='true'] {
    background: var(--fill);
    font-weight: 600;
    color: var(--ink);
  }

  .gi__link:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: -2px;
  }

  /* Onder 900: een rij chips die horizontaal scrolt en bovenaan blijft. */
  @media (max-width: 899px) {
    .gi {
      z-index: 2;
      height: auto;
      padding: 8px var(--inset);
      overflow: visible;
      border-right: 0;
      border-bottom: 1px solid var(--hairline);
      background: var(--bar-backdrop);
      backdrop-filter: blur(12px);
    }

    .gi__label {
      display: none;
    }

    .gi__list {
      flex-direction: row;
      gap: 6px;
      margin: 0 calc(-1 * var(--inset));
      padding: 2px var(--inset);
      overflow-x: auto;
      scrollbar-width: none;
    }

    .gi__link {
      min-height: var(--touch-target);
      padding: 0 14px;
      border: 1px solid var(--hairline-strong);
      border-radius: var(--radius-pill);
      font-size: 13px;
      white-space: nowrap;
    }

    .gi__link[aria-current='true'] {
      border-color: var(--ink);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .gi__link {
      transition: none;
    }
  }
</style>
