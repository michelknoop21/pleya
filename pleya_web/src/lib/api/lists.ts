/**
 * Verzamelingen en afspeellijsten (S19). De twee resources delen hun vorm, dus
 * één client met de soort als argument. Zoals in `personal.ts` hoort een client
 * bij één account: een schrijfactie na een accountwissel weigert hij.
 */
import type { components, operations } from './schema';
import type { PleyaClient } from './client';
import type { Collection, Item, Playlist } from './types';

export type ListKind = 'collection' | 'playlist';
type S = components['schemas'];
type ListQuery = NonNullable<operations['listCollections']['parameters']['query']>;

const noContent = (result: { response: Response; error?: unknown }) => result.response.status === 204
  ? { data: true as const, response: result.response }
  : { error: result.error, response: result.response };

/** Past bij de limiet van een pagina items; de server begrenst een lijst op 5000. */
const PAGE = 200;

/** Leest alle pagina's van een cursorlijst. */
export async function allPages<T>(read: (cursor?: string) => Promise<{ items: T[]; next_cursor?: string | null }>): Promise<T[]> {
  const items: T[] = [];
  let cursor: string | undefined;
  do {
    const page = await read(cursor);
    items.push(...page.items);
    cursor = page.next_cursor ?? undefined;
  } while (cursor);
  return items;
}

/**
 * De gekozen volgorde, toegepast op de lijst zoals hij nu is: `PUT` vervangt alles,
 * dus een rij die intussen verdween komt niet terug en een nieuwe rij gaat niet
 * verloren maar komt achteraan.
 */
export function mergeOrder(chosen: string[], current: string[]): string[] {
  const present = new Set(current);
  const kept = new Set(chosen.filter((id) => present.has(id)));
  return [...kept, ...current.filter((id) => !kept.has(id))];
}

/** De lijst zoals de modus Herordenen hem begon. */
export interface ReorderBase {
  items: Item[];
  /** Ontbreekt op een server zonder revisie; dan is vervangen onvoorwaardelijk. */
  revision?: number;
}

/** De gekozen volgorde als rijen, op de lijst zoals hij nu is. */
export function orderedItems(chosen: string[], current: Item[]): Item[] {
  const byId = new Map(current.map((item) => [item.id, item]));
  return mergeOrder(chosen, current.map((item) => item.id)).flatMap((id) => byId.get(id) ?? []);
}

export function listsApi(client: PleyaClient) {
  const generation = client.sessionGeneration;
  const assertAccount = () => {
    if (generation !== client.sessionGeneration) throw new Error('List action account changed');
  };
  const guarded = async <T>(run: () => Promise<T>): Promise<T> => {
    assertAccount();
    const value = await run();
    assertAccount();
    return value;
  };
  const collection = (id: string) => ({ params: { path: { collection_id: id } } });
  const playlist = (id: string) => ({ params: { path: { playlist_id: id } } });

  const api = {
    collections: (query: ListQuery = {}, signal?: AbortSignal) =>
      guarded(() => client.request(raw => raw.GET('/collections', { params: { query }, signal }))),
    playlists: (query: ListQuery = {}, signal?: AbortSignal) =>
      guarded(() => client.request(raw => raw.GET('/playlists', { params: { query }, signal }))),
    collection: (id: string, signal?: AbortSignal): Promise<Collection> =>
      guarded(() => client.request(raw => raw.GET('/collections/{collection_id}', { ...collection(id), signal }))),
    playlist: (id: string, signal?: AbortSignal): Promise<Playlist> =>
      guarded(() => client.request(raw => raw.GET('/playlists/{playlist_id}', { ...playlist(id), signal }))),
    createCollection: (body: S['CreateCollectionRequest']): Promise<Collection> =>
      guarded(() => client.request(raw => raw.POST('/collections', { body }))),
    createPlaylist: (title: string): Promise<Playlist> =>
      guarded(() => client.request(raw => raw.POST('/playlists', { body: { title } }))),
    updateCollection: (id: string, body: S['UpdateCollectionRequest']): Promise<Collection> =>
      guarded(() => client.request(raw => raw.PATCH('/collections/{collection_id}', { ...collection(id), body }))),
    updatePlaylist: (id: string, title: string): Promise<Playlist> =>
      guarded(() => client.request(raw => raw.PATCH('/playlists/{playlist_id}', { ...playlist(id), body: { title } }))),
    remove: (kind: ListKind, id: string): Promise<true> =>
      guarded(() => client.request(async raw => noContent(await (kind === 'collection'
        ? raw.DELETE('/collections/{collection_id}', collection(id))
        : raw.DELETE('/playlists/{playlist_id}', playlist(id)))))),
    items: (kind: ListKind, id: string, query: { cursor?: string; limit?: number } = {}, signal?: AbortSignal) =>
      guarded(() => client.request(raw => kind === 'collection'
        ? raw.GET('/collections/{collection_id}/items', { params: { path: { collection_id: id }, query }, signal })
        : raw.GET('/playlists/{playlist_id}/items', { params: { path: { playlist_id: id }, query }, signal }))),
    /** Alle pagina's, voor herordenen en "Alles afspelen". */
    allItems: (kind: ListKind, id: string, signal?: AbortSignal): Promise<Item[]> =>
      allPages((cursor) => api.items(kind, id, { limit: PAGE, ...(cursor ? { cursor } : {}) }, signal)),
    /**
     * Wat de modus Herordenen nodig heeft: de revisie vóór de rijen, zodat een wijziging
     * tussen die twee lezingen op de veilige kant valt.
     */
    async readForReorder(kind: ListKind, id: string, signal?: AbortSignal): Promise<ReorderBase> {
      const list = await (kind === 'collection' ? api.collection(id, signal) : api.playlist(id, signal));
      const items = await api.allItems(kind, id, signal);
      return { items, ...(list.revision !== undefined ? { revision: list.revision } : {}) };
    },
    /**
     * Herordenen duurt minuten. `revision` is wat de modus zag, dus een wijziging in die tijd
     * wordt `library.list_conflict` in plaats van een stil verlies. De rijen worden toch vlak
     * vóór het vervangen gelezen: een item dat uit de catalogus verdween telt niet als revisie.
     */
    async saveOrder(kind: ListKind, id: string, order: string[], revision?: number, signal?: AbortSignal): Promise<true> {
      const current = await api.allItems(kind, id, signal);
      return api.replaceItems(kind, id, mergeOrder(order, current.map((item) => item.id)), revision);
    },
    replaceItems: (kind: ListKind, id: string, itemIds: string[], baseRevision?: number): Promise<true> =>
      guarded(() => client.request(async raw => {
        const body = { item_ids: itemIds, ...(baseRevision !== undefined ? { base_revision: baseRevision } : {}) };
        return noContent(await (kind === 'collection'
          ? raw.PUT('/collections/{collection_id}/items', { ...collection(id), body })
          : raw.PUT('/playlists/{playlist_id}/items', { ...playlist(id), body })));
      })),
    addItems: (kind: ListKind, id: string, itemIds: string[]): Promise<true> =>
      guarded(() => client.request(async raw => {
        const body = { item_ids: itemIds };
        return noContent(await (kind === 'collection'
          ? raw.POST('/collections/{collection_id}/items', { ...collection(id), body })
          : raw.POST('/playlists/{playlist_id}/items', { ...playlist(id), body })));
      })),
    removeItem: (kind: ListKind, id: string, itemId: string): Promise<true> =>
      guarded(() => client.request(async raw => noContent(await (kind === 'collection'
        ? raw.DELETE('/collections/{collection_id}/items/{item_id}', { params: { path: { collection_id: id, item_id: itemId } } })
        : raw.DELETE('/playlists/{playlist_id}/items/{item_id}', { params: { path: { playlist_id: id, item_id: itemId } } }))))),
  };
  return api;
}

/** Een onbekende zichtbaarheid (3.2) toont de client als gedeeld. */
export function knownVisibility(value: string): 'private' | 'everyone' | 'users' | null {
  return value === 'private' || value === 'everyone' || value === 'users' ? value : null;
}

/** Waar de speler na dit item heen gaat in een lijst; null aan het eind. */
export function nextInList(items: Pick<Item, 'id'>[], currentId: string): string | null {
  const at = items.findIndex(item => item.id === currentId);
  return at >= 0 ? (items[at + 1]?.id ?? null) : null;
}
