import type { Item } from '#lib/api/types.js';

export const movie = (id: string, title: string, year: number): Item => ({
  id, title, year, kind: 'movie', added_at: '2026-11-02T12:00:00Z', duration_ms: 9_960_000,
  artwork: { poster_id: `${id}-poster`, backdrop_id: `${id}-backdrop` },
  versions: [{ id: `version-${id}`, container: 'mp4', duration_ms: 9_960_000, file_count: 1 }]
});

export const featured: Item = {
  ...movie('dune2', 'Dune: Part Two', 2024), genres: ['Sciencefiction'], content_rating: '12',
  summary: 'Paul Atreides verenigt zich met Chani en de Fremen en zint op wraak op de samenzweerders die zijn familie vernietigden.'
};
export const recent = [featured, movie('interstellar', 'Interstellar', 2014), movie('anora', 'Anora', 2024), movie('conclave', 'Conclave', 2024), movie('barbie', 'Barbie', 2023), movie('oppenheimer', 'Oppenheimer', 2023)];
export const continuing: Item[] = [
  { ...movie('severance', 'In Perpetuity', 2022), id: 'severance-episode', kind: 'episode', index: 3, duration_ms: 3_000_000, user_state: { watched: false, position_ms: 1_860_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' } },
  { ...recent[1]!, duration_ms: 10_140_000, user_state: { watched: false, position_ms: 6_180_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' } },
  { ...movie('andor', 'The Eye', 2022), id: 'andor-episode', kind: 'episode', index: 6, duration_ms: 2_700_000, user_state: { watched: false, position_ms: 900_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' } },
  { ...featured, user_state: { watched: false, position_ms: 3_600_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' } },
  { ...movie('fallout', 'The Trap', 2024), id: 'fallout-episode', kind: 'episode', index: 6, duration_ms: 3_600_000, user_state: { watched: false, position_ms: 2_700_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' } }
];
// Recent toegevoegd · Series zoals Pleya Server hem levert: losse afleveringen,
// een deel zonder eigen still (S22.4). De rail leest serie en seizoen via getParent.
const added = '2026-11-05T12:00:00Z';
const ancestors: Item[] = [
  { id: 'moon-news', kind: 'show', title: 'Moon News and Markets', added_at: added, artwork: { poster_id: 'moon-news-poster', backdrop_id: 'moon-news-backdrop' } },
  { id: 'moon-news-s1', kind: 'season', title: 'Seizoen 1', parent_id: 'moon-news', index: 1, added_at: added },
  { id: 'media-room', kind: 'show', title: 'Media Room Slash Dungeon', added_at: added, artwork: { poster_id: 'media-room-poster', backdrop_id: null } },
  { id: 'media-room-s1', kind: 'season', title: 'Seizoen 1', parent_id: 'media-room', index: 1, added_at: added }
];
const episodeOf = (id: string, season: string, index: number, still: string | null): Item => ({
  id, kind: 'episode', title: 'TBA', parent_id: season, index, added_at: added, artwork: { poster_id: still, backdrop_id: null }
});
export const newEpisodes: Item[] = [
  episodeOf('moon-news-a6', 'moon-news-s1', 6, null),
  episodeOf('media-room-a2', 'media-room-s1', 2, 'media-room-a2-still'),
  episodeOf('media-room-a3', 'media-room-s1', 3, null),
  episodeOf('moon-news-a5', 'moon-news-s1', 5, 'moon-news-a5-still')
];
export async function fixtureParent(id: string): Promise<Item> {
  const found = ancestors.find((item) => item.id === id);
  if (!found) throw new Error('404');
  return found;
}
export const coverTitles: Record<string, string> = { 'severance-episode': 'Severance', 'andor-episode': 'Andor', 'fallout-episode': 'Fallout' };
