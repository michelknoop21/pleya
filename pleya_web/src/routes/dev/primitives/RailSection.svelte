<!--
  De drie rijen van specimen v3, naast beeld 01: Continue watching met
  voortgang en een doorklikpad, Next up met vijf afleveringen in de brede vorm
  en zonder doorklikpad, en Recently added met twaalf titels, meer dan er op
  1600 passen, zodat de fade rechts te zien is. Galerijlabels zijn gewone
  Nederlandse tekst: de route bestaat alleen in ontwikkeling.

  De rail springt zelf in op --inset, omdat Home hem zonder paginapadding
  plaatst. De galerij heeft die inzet al, dus de negatieve marge hier heft hem
  op; de bleed loopt daardoor tot de rand van de galerijkolom.

  Twee rijen geven een `card`-snippet mee, zoals een route dat doet die meer
  weet dan het item zelf: de serieposter en afleveringsregel in Continue
  watching, en de nieuw-punten in Recently added.
-->
<script lang="ts">
  import HubRail from '$lib/components/HubRail.svelte';
  import MediaCard from '$lib/components/MediaCard.svelte';
  import { setArtworkLoader } from '$lib/components/artworkLoader';
  import type { Item } from '$lib/api/types';
  import { t } from '$lib/i18n';
  import { formatDuration } from '$lib/util/format';
  import GallerySection from './GallerySection.svelte';
  import { demoArtworkLoader } from './demoArtwork';

  setArtworkLoader(demoArtworkLoader);

  const MIN = 60_000;

  function demo(id: string, title: string, patch: Partial<Item> = {}): Item {
    return { id, kind: 'movie', title, added_at: '2026-10-01T00:00:00Z', ...patch } as Item;
  }

  function progress(total: number, seen: number): Partial<Item> {
    return {
      duration_ms: total * MIN,
      user_state: {
        position_ms: seen * MIN,
        watched: false,
        play_count: 0,
        updated_at: '2026-10-01T00:00:00Z'
      }
    };
  }

  /** Een aflevering in Verder kijken: serieposter, regel met seizoen en aflevering. */
  interface Resume {
    item: Item;
    poster: string;
    episode?: string;
  }

  function episode(key: string, title: string, code: string, total: number, seen: number): Resume {
    const item = demo(`${key}-resume`, title, { kind: 'episode', ...progress(total, seen) });
    return { item, poster: key, episode: code };
  }

  function movie(key: string, title: string, total: number, seen: number): Resume {
    const item = demo(`${key}-resume`, title, { artwork: { poster_id: key }, ...progress(total, seen) });
    return { item, poster: key };
  }

  const resume: Resume[] = [
    episode('sev', 'Severance', 'S2 · E3', 81, 50),
    movie('dune', 'Dune', 155, 83),
    episode('bear', 'The Bear', 'S3 · E1', 40, 22),
    movie('opp', 'Oppenheimer', 180, 56),
    episode('slow', 'Slow Horses', 'S4 · E2', 50, 10),
    movie('poor', 'Poor Things', 141, 93),
    episode('andor', 'Andor', 'S2 · E6', 65, 43),
    movie('hold', 'The Holdovers', 133, 34),
    episode('shogun', 'Shogun', 'S1 · E5', 60, 48),
    episode('arcane', 'Arcane', 'S2 · E2', 47, 14)
  ];
  const resumeByID = new Map(resume.map((r) => [r.item.id, r]));

  function remaining(item: Item): string {
    const state = item.user_state;
    const left = formatDuration((item.duration_ms ?? 0) - (state?.position_ms ?? 0)) ?? '';
    return t('card.remaining', { duration: left });
  }

  function resumeSubtitle(entry: Resume): string {
    const left = remaining(entry.item);
    return entry.episode ? `${entry.episode} · ${left}` : left;
  }

  const nextUpRows: [string, string, number, string][] = [
    ['fallout', 'Fallout', 7, 'S1 · E7 · The Radio'],
    ['shogun', 'Shogun', 5, 'S1 · E5 · Broken to the Fist'],
    ['arcane', 'Arcane', 2, 'S2 · E2 · Watch It All Burn'],
    ['tlou', 'The Last of Us', 3, 'S2 · E3 · The Path'],
    ['penguin', 'The Penguin', 4, "S1 · E4 · Cent'anni"]
  ];
  const nextUp: Item[] = nextUpRows.map(([key, title, index]) =>
    demo(`${key}-next`, title, { kind: 'episode', index, artwork: { backdrop_id: `${key}@wide` } })
  );
  // De afleveringsregel komt van de aanroeper, net als in Verder kijken.
  const nextUpLine = new Map(nextUpRows.map(([key, , , line]) => [`${key}-next`, line]));

  const recentRows: [string, string, number][] = [
    ['anora', 'Anora', 2024],
    ['conclave', 'Conclave', 2024],
    ['nosf', 'Nosferatu', 2024],
    ['glad', 'Gladiator II', 2024],
    ['civil', 'Civil War', 2024],
    ['furiosa', 'Furiosa', 2024],
    ['wicked', 'Wicked', 2024],
    ['subst', 'The Substance', 2024],
    ['opp', 'Oppenheimer', 2023],
    ['inter', 'Interstellar', 2014],
    ['poor', 'Poor Things', 2023],
    ['dune2', 'Dune: Part Two', 2024]
  ];
  const recent: Item[] = recentRows.map(([key, title, year]) =>
    demo(`${key}-recent`, title, { year, artwork: { poster_id: key } })
  );
  // De aanroeper bepaalt wat nieuw is (S8); hier de eerste twee, zoals het specimen.
  const fresh = new Set(recent.slice(0, 2).map((item) => item.id));
</script>

{#snippet resumeCard(item: Item, index: number)}
  {@const entry = resumeByID.get(item.id)}
  <MediaCard
    {item}
    shape="poster"
    eager={index < 8}
    artworkId={entry?.poster}
    subtitle={entry ? resumeSubtitle(entry) : undefined}
  />
{/snippet}

{#snippet nextUpCard(item: Item, index: number)}
  <MediaCard
    {item}
    shape="wide"
    eager={index < 8}
    subtitle={nextUpLine.get(item.id)}
  />
{/snippet}

{#snippet recentCard(item: Item, index: number)}
  <MediaCard {item} shape="poster" eager={index < 8} isNew={fresh.has(item.id)} />
{/snippet}

<GallerySection id="rail" title="Rail">
  <div class="rs">
    <div class="rs__bleed">
      <HubRail
        title="Continue watching"
        items={resume.map((r) => r.item)}
        href="/dev/primitives#rail"
        card={resumeCard}
      />
    </div>
    <div>
      <div class="rs__bleed">
        <HubRail title="Next up" items={nextUp} card={nextUpCard} />
      </div>
      <p class="gs__caption">zonder href: geen "View all"; alleen afleveringen, dus de brede vorm</p>
    </div>
    <div>
      <div class="rs__bleed">
        <HubRail
          title="Recently added in Films"
          items={recent}
          href="/dev/primitives#rail"
          card={recentCard}
        />
      </div>
      <p class="gs__caption">
        muis boven de rail (vanaf 900, alleen met hover): pijlen verschijnen, de linker is uit aan het begin
      </p>
    </div>
  </div>
</GallerySection>

<style>
  .rs {
    display: flex;
    flex-direction: column;
    gap: 28px;
  }

  .rs__bleed {
    margin-inline: calc(-1 * var(--inset));
  }
</style>
