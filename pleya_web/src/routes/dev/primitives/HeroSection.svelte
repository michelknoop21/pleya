<!--
  De hero in vier varianten, naast specimen v3 en beeld 01: met afspeelknop en
  synopsis (zoals hij na PS-4W en PS-7N wordt), zonder afspeelknop (zoals elke
  route hem in deze grens aanroept), een lange titel die over meer regels
  breekt, en zonder artwork. Galerijlabels zijn gewone Nederlandse tekst: de
  route bestaat alleen in ontwikkeling.

  Hero springt zelf in op --inset, omdat Home hem zonder paginapadding
  plaatst. De galerij heeft die inzet al, dus de negatieve marge hier heft
  hem op en de hero staat even breed als in de app.

  Het artwork is gegenereerd (demoArtwork.ts, variant `@hero` zonder tekst)
  en loopt via de loader-context het echte laadpad van Artwork.
-->
<script lang="ts">
  import Hero from '$lib/components/Hero.svelte';
  import { setArtworkLoader } from '$lib/components/artworkLoader';
  import type { Item } from '$lib/api/types';
  import GallerySection from './GallerySection.svelte';
  import { demoArtworkLoader } from './demoArtwork';

  setArtworkLoader(demoArtworkLoader);

  const MIN = 60_000;

  function movie(id: string, patch: Partial<Item>): Item {
    return { id, kind: 'movie', title: id, added_at: '2026-10-01T00:00:00Z', ...patch } as Item;
  }

  interface Variant {
    note: string;
    item: Item;
    summary?: string;
    playHref?: string;
  }

  const variants: Variant[] = [
    {
      note: 'A · met playHref en summary (Afspelen pas na PS-4W, synopsis na PS-7N)',
      item: movie('dune2', {
        title: 'Dune: Part Two',
        year: 2024,
        duration_ms: 166 * MIN,
        // Het verloop zonder zon, zoals hero A in het specimen.
        artwork: { backdrop_id: 'dune@hero' }
      }),
      summary:
        'Paul Atreides trekt met de Fremen de woestijn in en moet kiezen tussen wraak en de toekomst die hij in zijn visioenen ziet.',
      playHref: '/dev/primitives#hero'
    },
    {
      note: 'B · zoals de routes hem in deze grens aanroepen: geen playHref, geen summary',
      item: movie('opp', {
        title: 'Oppenheimer',
        year: 2023,
        duration_ms: 180 * MIN,
        artwork: { backdrop_id: 'opp@hero' }
      })
    },
    {
      note: 'C · lange titel, breekt over meer regels',
      item: movie('rotk', {
        title: 'The Lord of the Rings: The Return of the King',
        year: 2003,
        duration_ms: 201 * MIN,
        artwork: { backdrop_id: 'rotk@hero' }
      })
    },
    {
      note: 'D · zonder artwork',
      item: movie('zone', { title: 'The Zone of Interest', year: 2023, duration_ms: 105 * MIN })
    }
  ];
</script>

<GallerySection id="hero" title="Hero">
  {#each variants as variant (variant.item.id)}
    <div class="hs">
      <p class="gs__caption">{variant.note}</p>
      <div class="hs__bleed">
        <Hero
          item={variant.item}
          summary={variant.summary}
          playHref={variant.playHref}
          label={variant.item.title}
        />
      </div>
    </div>
  {/each}
</GallerySection>

<style>
  .hs {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
  }

  .hs__bleed {
    margin-inline: calc(-1 * var(--inset));
  }
</style>
