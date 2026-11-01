/**
 * Leesbare namen voor de wire-types uit het gegenereerde contract.
 *
 * Dit is een alias-laag en geen tweede modellaag: elke naam hieronder wijst
 * rechtstreeks naar `components["schemas"]` uit `schema.d.ts`, zodat een
 * contractwijziging hier een typefout geeft in plaats van een stille afwijking.
 */
import type { components, operations } from './schema';

type S = components['schemas'];

export type Id = S['Id'];
export type Info = S['Info'];
export type Capabilities = S['Capabilities'];
export type ServerDetail = S['ServerDetail'];
export type TokenPair = S['TokenPair'];
export type Library = S['Library'];
export type LibraryList = S['LibraryList'];
export type LibraryKind = S['LibraryKind'];
export type LibraryManaged = S['LibraryManaged'];
export type CreateLibraryRequest = S['CreateLibraryRequest'];
export type UpdateLibraryRequest = S['UpdateLibraryRequest'];
export type MetadataCoverage = S['MetadataCoverage'];
export type Item = S['Item'];
export type ItemKind = S['ItemKind'];
export type ItemPage = S['ItemPage'];
export type HistoryEntry = S['HistoryEntry'];
export type Collection = S['Collection'];
export type CollectionVisibility = S['CollectionVisibility'];
export type Playlist = S['Playlist'];
export type Download = S['Download'];
export type WatchHistory = S['WatchHistory'];
export type WatchHistoryEntry = S['WatchHistoryEntry'];
export type Facets = S['Facets'];
export type FacetValue = S['FacetValue'];
export type LibraryItemsQuery = NonNullable<operations['listLibraryItems']['parameters']['query']>;
export type Artwork = S['Artwork'];
export type Version = S['Version'];
export type VideoStream = S['VideoStream'];
export type AudioStream = S['AudioStream'];
export type SubtitleStream = S['SubtitleStream'];
export type User = S['User'];
export type Role = S['Role'];
export type Scan = S['Scan'];
export type Job = S['Job'];
export type StorageRoot = S['StorageRoot'];
export type StreamSessionSummary = S['StreamSessionSummary'];
export type TranscodeSessionList = S['TranscodeSessionList'];
export type ErrorEnvelope = S['ErrorEnvelope'];

/** De sorteringen die `GET /libraries/{id}/items` accepteert. */
export const SORT_OPTIONS = [
  'title',
  '-title',
  'added_at',
  '-added_at',
  'year',
  '-year',
  'last_played_at',
  '-last_played_at',
  'duration',
  '-duration'
] as const satisfies readonly NonNullable<LibraryItemsQuery['sort']>[];

export const LEGACY_SORT_OPTIONS = SORT_OPTIONS.slice(0, 6);

export type SortOption = (typeof SORT_OPTIONS)[number];

export function isSortOption(value: string): value is SortOption {
  return (SORT_OPTIONS as readonly string[]).includes(value);
}

// Serverinstellingen en diagnostiek (S10.5).
export type Settings = S['Settings'];
export type SettingsPatch = S['SettingsPatch'];
export type SettingSource = S['SettingSource'];
export type ServerEnvironment = S['ServerEnvironment'];
export type ServerLog = S['ServerLog'];
export type LogLevel = S['LogLevel'];
export type ConnectivityCheck = S['ConnectivityCheck'];
export type MetadataAttentionList = S['MetadataAttentionList'];
export type MetadataAttention = S['MetadataAttention'];
export type MetadataAlternative = S['MetadataAlternative'];
export type MetadataMatch = S['MetadataMatch'];
export type TranscodeSession = S['TranscodeSession'];

// Back-ups en terugzetten (S25.6).
export type Backup = S['Backup'];
export type BackupList = S['BackupList'];
export type BackupRestoreTest = S['BackupRestoreTest'];

export type MetadataSearchCandidate = S['MetadataSearchCandidate'];
export type MetadataSearchResults = S['MetadataSearchResults'];
export type MetadataCandidateDetails = S['MetadataCandidateDetails'];
export type MetadataMatchStatus = S['MetadataMatchStatus'];
