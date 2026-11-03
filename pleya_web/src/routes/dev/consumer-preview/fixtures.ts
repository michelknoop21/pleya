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
export const coverTitles: Record<string, string> = { 'severance-episode': 'Severance', 'andor-episode': 'Andor', 'fallout-episode': 'Fallout' };
