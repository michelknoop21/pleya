import type { Item } from '../api/types';

type DetailRating = NonNullable<Item['external_ratings']>[number];

/** Old, partial or invalid presentation data must not break the detail page. */
export function externalRatingsForDetail(input: unknown): DetailRating[] {
  if (!Array.isArray(input)) return [];
  const ratings: DetailRating[] = [];
  for (const value of input) {
    if (ratings.length === 8) break;
    if (!value || typeof value !== 'object') continue;
    const { source, value: score, max_value: max, vote_count: votes } = value;
    if (typeof source !== 'string' || !source.trim() || source.length > 32 ||
      typeof score !== 'number' || !Number.isFinite(score) || typeof max !== 'number' ||
      !Number.isFinite(max) || max <= 0 || max > 100 || score < 0 || score > max ||
      (votes !== undefined && (!Number.isInteger(votes) || votes < 0))) continue;
    ratings.push({ source: source.trim(), value: score, max_value: max, ...(votes === undefined ? {} : { vote_count: votes }) });
  }
  return ratings;
}
