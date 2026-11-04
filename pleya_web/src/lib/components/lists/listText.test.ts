import { describe, expect, it } from 'vitest';
import type { Collection, Item } from '../../api/types';
import { collectionMeta, playlistMeta, rowMeta, rowPercent } from './listText';

const collection = (over: Partial<Collection>): Collection => ({
  id: 'c', title: 'Set', owner: { id: 'o', username: 'sanne' }, is_owner: true, visibility: 'private',
  item_count: 2, artwork: [], created_at: '2026-10-30T00:00:00Z', updated_at: '2026-10-30T00:00:00Z', ...over
});

describe('list text', () => {
  it('names the owner of a list that is not mine', () => {
    expect(collectionMeta(collection({ is_owner: false, visibility: 'everyone' }))).toBe('2 titles · by sanne');
  });

  it('shows who a collection is visible to, only for its owner', () => {
    expect(collectionMeta(collection({ visibility: 'users', shared_with: [{ id: 'k', username: 'kids' }] }))).toBe('2 titles · visible to kids');
    expect(collectionMeta(collection({}))).toBe('2 titles · private');
  });

  it('shows a visibility it does not know as shared', () => {
    expect(collectionMeta(collection({ visibility: 'friends' as Collection['visibility'] }))).toBe('2 titles · shared');
  });

  it('sums a playlist into a count and a duration', () => {
    expect(playlistMeta({ id: 'p', title: 'P', item_count: 1, duration_ms: 5_400_000, artwork: [], created_at: '', updated_at: '' })).toBe('1 title · 1h 30m');
  });

  it('carries the watch state of a row', () => {
    const base: Item = { id: 'i', kind: 'movie', title: 'T', year: 2014, added_at: '', duration_ms: 6_000_000 };
    const state = { position_ms: 0, watched: false, play_count: 0, updated_at: '' };
    expect(rowMeta(base)).toBe('2014 · 1h 40m');
    expect(rowMeta({ ...base, user_state: { ...state, watched: true } })).toContain('watched');
    expect(rowPercent({ ...base, user_state: { ...state, position_ms: 3_000_000 } })).toBe(50);
    expect(rowPercent(base)).toBeNull();
  });
});
