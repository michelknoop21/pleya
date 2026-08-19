/**
 * Leesbare namen voor de wire-types uit het gegenereerde contract.
 *
 * Dit is een alias-laag en geen tweede modellaag: elke naam hieronder wijst
 * rechtstreeks naar `components["schemas"]` uit `schema.d.ts`, zodat een
 * contractwijziging hier een typefout geeft in plaats van een stille afwijking.
 */
import type { components } from './schema';

type S = components['schemas'];

export type Id = S['Id'];
export type Info = S['Info'];
export type Capabilities = S['Capabilities'];
export type ServerDetail = S['ServerDetail'];
export type TokenPair = S['TokenPair'];
export type Library = S['Library'];
export type LibraryList = S['LibraryList'];
export type LibraryKind = S['LibraryKind'];
export type Item = S['Item'];
export type ItemKind = S['ItemKind'];
export type ItemPage = S['ItemPage'];
export type Artwork = S['Artwork'];
export type Version = S['Version'];
export type VideoStream = S['VideoStream'];
export type AudioStream = S['AudioStream'];
export type SubtitleStream = S['SubtitleStream'];
export type ErrorEnvelope = S['ErrorEnvelope'];

/** De sorteringen die `GET /libraries/{id}/items` accepteert. */
export const SORT_OPTIONS = [
  'title',
  '-title',
  'added_at',
  '-added_at',
  'year',
  '-year'
] as const;

export type SortOption = (typeof SORT_OPTIONS)[number];

export function isSortOption(value: string): value is SortOption {
  return (SORT_OPTIONS as readonly string[]).includes(value);
}
