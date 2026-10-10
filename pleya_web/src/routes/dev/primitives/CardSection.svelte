<!--
  De kaartstaten van northstar-scherm 16, in de volgorde van specimen v3.
  Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen
  in ontwikkeling. Alleen de demoknoppen gaan door t(), want die labels zijn
  wat een schermlezer op een echte kaart hoort.

  Hover en toetsenbordfocus zijn echte staten en geen nagebootste: beweeg de
  muis over de tweede kaart of tab naar de derde. Het screenshotscript doet
  allebei tegelijk (scripts/primitives-shots.ts).

  Het artwork is gegenereerd (demoArtwork.ts) en komt via de loader-context
  binnen, dus de kaart loopt het echte laadpad van Artwork.
-->
<script lang="ts">
  import MediaCard from '$lib/components/MediaCard.svelte';
  import { setArtworkLoader } from '$lib/components/artworkLoader';
  import type { Item } from '$lib/api/types';
  import { t } from '$lib/i18n';
  import { formatDuration } from '$lib/util/format';
  import GallerySection from './GallerySection.svelte';
  import { demoArtworkLoader } from './demoArtwork';

  setArtworkLoader(demoArtworkLoader);

  const MIN = 60_000;

  function demo(id: string, patch: Partial<Item>): Item {
    return { id, kind: 'movie', title: id, added_at: '2026-10-01T00:00:00Z', ...patch } as Item;
  }

  function watchedState(watched: boolean, position_ms = 0): Item['user_state'] {
    return { position_ms, watched, play_count: watched ? 1 : 0, updated_at: '2026-10-01T00:00:00Z' };
  }

  const dune2 = demo('dune2', { title: 'Dune: Part Two', year: 2024, artwork: { poster_id: 'dune2' } });
  const version = (id: string) => ({ id }) as NonNullable<Item['versions']>[number];

  interface Cell {
    note: string;
    item: Item;
    demo?: 'hover' | 'focus';
    shape?: 'poster' | 'wide';
    isNew?: boolean;
    artworkId?: string | null;
    subtitle?: string;
    actions?: boolean;
  }

  // Severance S2E3: 50 van 81 minuten gezien, dus 31 over (62 procent).
  const sevLeft = t('card.remaining', { duration: formatDuration(31 * MIN) ?? '' });

  const cells: Cell[] = [
    { note: 'rust', item: dune2 },
    {
      note: 'muis erover: witte ring, lift, acties onderin (afspelen · mijn lijst · meer)',
      item: dune2,
      demo: 'hover',
      actions: true
    },
    { note: 'toetsenbordfocus: ring op een gap, geen lift', item: dune2, demo: 'focus' },
    {
      note: 'voortgang uit user_state',
      item: demo('dune', {
        title: 'Dune',
        year: 2021,
        duration_ms: 116 * MIN,
        user_state: watchedState(false, 44 * MIN),
        artwork: { poster_id: 'dune' }
      })
    },
    {
      note: 'gezien',
      item: demo('inter', {
        title: 'Interstellar',
        year: 2014,
        user_state: watchedState(true),
        artwork: { poster_id: 'inter' }
      })
    },
    {
      note: 'nieuw sinds je laatste bezoek: amber punt',
      item: demo('anora', { title: 'Anora', year: 2024, artwork: { poster_id: 'anora' } }),
      isNew: true
    },
    {
      note: 'aflevering in Verder kijken: serieposter, afleveringsregel',
      item: demo('sev-s2e3', {
        kind: 'episode',
        title: 'Severance',
        index: 3,
        duration_ms: 81 * MIN,
        user_state: watchedState(false, 50 * MIN),
        artwork: { backdrop_id: 'sev@wide' }
      }),
      shape: 'poster',
      artworkId: 'sev',
      subtitle: `S2 · E3 · ${sevLeft}`
    },
    {
      note: 'volgende aflevering: 16:9, breedte 1,78 × poster',
      item: demo('fallout-s1e7', {
        kind: 'episode',
        title: 'Fallout',
        index: 7,
        artwork: { backdrop_id: 'fallout@wide' }
      }),
      shape: 'wide',
      subtitle: 'S1 · E7 · The Radio'
    },
    {
      note: 'geen artwork: titel en jaar op het paneel',
      item: demo('zone', { title: 'The Zone of Interest', year: 2023 })
    },
    {
      note: 'meerdere versies (4K en 1080p) op één item',
      item: demo('opp', {
        title: 'Oppenheimer',
        year: 2023,
        versions: [version('4k'), version('1080p')],
        artwork: { poster_id: 'opp' }
      })
    },
    {
      note: 'gezien én nieuw: gezien wint, geen punt',
      item: demo('civil', {
        title: 'Civil War',
        year: 2024,
        user_state: watchedState(true),
        artwork: { poster_id: 'civil' }
      }),
      isNew: true
    }
  ];
</script>

{#snippet demoActions()}
  <button type="button" class="card-action card-action--primary" aria-label={t('dev.play')}>
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" class="ca__fill">
      <path d="M7 4.5v15l12.5-7.5z" />
    </svg>
  </button>
  <button type="button" class="card-action" aria-label={t('dev.myList')}>
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" class="ca__line">
      <path d="M12 5v14M5 12h14" />
    </svg>
  </button>
  <button type="button" class="card-action" aria-label={t('dev.more')}>
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" class="ca__line ca__dots">
      <path d="M6 12h.01M12 12h.01M18 12h.01" />
    </svg>
  </button>
{/snippet}

<GallerySection id="kaarten" title="Kaarten">
  <div class="cs">
    {#each cells as cell (cell.note)}
      <div class="cs__cell" class:cs__cell--wide={cell.shape === 'wide'} data-demo={cell.demo}>
        <MediaCard
          item={cell.item}
          eager
          shape={cell.shape}
          isNew={cell.isNew}
          artworkId={cell.artworkId}
          subtitle={cell.subtitle}
          actions={cell.actions ? demoActions : undefined}
        />
        <p class="cs__note">{cell.note}</p>
      </div>
    {/each}
  </div>
</GallerySection>

<style>
  .cs {
    display: flex;
    flex-wrap: wrap;
    gap: 22px var(--rail-gap);
    align-items: flex-start;
  }

  /* De cel geeft de kaart zijn breedte, zoals een rij of raster dat straks doet. */
  .cs__cell {
    width: var(--poster-w);
  }

  .cs__cell--wide {
    width: calc(var(--poster-w) * 1.78);
  }

  .cs__note {
    margin: var(--space-half) 0 0;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
    text-align: center;
  }

  .ca__fill {
    fill: currentColor;
    margin-left: 2px;
  }

  .ca__line {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .ca__dots {
    stroke-width: 3;
  }
</style>
