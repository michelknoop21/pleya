import type { operations } from './schema';
import type { PleyaClient } from './client';
import { randomId } from '../auth/device';
import { playbackApi } from '../player/playbackApi';

// These mutations return 204; the shared client unwraps a value or an error.
const noContent = (result: { response: Response; error?: unknown }) => result.response.status === 204
  ? { data: true as const, response: result.response }
  : { error: result.error, response: result.response };

type FavoritesQuery = NonNullable<operations['listFavorites']['parameters']['query']>;
type HistoryQuery = NonNullable<operations['getHistory']['parameters']['query']>;

export function personalApi(client: PleyaClient) {
  const generation = client.sessionGeneration;
  const watch = playbackApi(client);
  const assertAccount = () => {
    if (generation !== client.sessionGeneration) throw new Error('Personal action account changed');
  };
  return {
    async favorites(query: FavoritesQuery = {}, signal?: AbortSignal) {
      assertAccount();
      const page = await client.request(raw => raw.GET('/favorites', { params: { query }, signal }));
      assertAccount();
      return page;
    },
    async history(query: HistoryQuery = {}, signal?: AbortSignal) {
      assertAccount();
      const page = await client.request(raw => raw.GET('/history', { params: { query }, signal }));
      assertAccount();
      return page;
    },
    async downloads(signal?: AbortSignal) {
      assertAccount();
      const list = await client.request(raw => raw.GET('/downloads', { signal }));
      assertAccount();
      return list.items;
    },
    async deleteDownload(downloadId: string): Promise<void> {
      assertAccount();
      await client.request(async raw => noContent(await raw.DELETE('/downloads/{download_id}', { params: { path: { download_id: downloadId } } })));
      assertAccount();
    },
    async setFavorite(itemId: string, favorite: boolean): Promise<void> {
      assertAccount();
      const params = { path: { item_id: itemId } };
      await client.request(async raw => noContent(await (favorite ? raw.PUT('/favorites/{item_id}', { params }) : raw.DELETE('/favorites/{item_id}', { params }))));
      assertAccount();
    },
    async setRating(itemId: string, rating: number | null): Promise<void> {
      assertAccount();
      if (rating !== null && (!Number.isInteger(rating) || rating < 1 || rating > 10)) throw new RangeError('Rating must be 1..10');
      const params = { path: { item_id: itemId } };
      await client.request(async raw => noContent(await (rating === null ? raw.DELETE('/ratings/{item_id}', { params }) : raw.PUT('/ratings/{item_id}', { params, body: { rating } }))));
      assertAccount();
    },
    async setWatched(itemId: string, watched: boolean, durationMs?: number) {
      assertAccount();
      if (durationMs !== undefined && (!Number.isSafeInteger(durationMs) || durationMs < 0)) throw new RangeError('Invalid duration');
      return watch.reportWatchState({
        item_id: itemId, session_id: randomId(),
        position_ms: watched ? durationMs ?? 0 : 0,
        ...(durationMs !== undefined ? { duration_ms: durationMs } : {}),
        occurred_at: new Date().toISOString(), completed: watched,
        explicit_action: watched ? 'mark_watched' : 'mark_unwatched'
      });
    }
  };
}
