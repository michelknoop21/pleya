/** Alleen synthetische componenttests; product gebruikt uitsluitend de typed API. */
import type { MetadataFields, Item } from '../../api/types';
import { clientFor, json, apiError } from '../libraryFake';

export function metadataFixture(id = 'i1'): MetadataFields {
  return { item_id: id, fields: {
    title: { value: id === 'i1' ? 'First film' : 'Second film', source: 'scanner', locked: false },
    year: { value: 2001, source: 'scanner', locked: false },
    summary: { value: id === 'i1' ? 'Source summary' : 'Second summary', source: 'nfo', locked: false },
    genres: { value: ['Drama'], source: 'tmdb', locked: false },
    content_rating: { value: '12', source: 'tmdb', locked: false },
    people: { value: [{ name: 'Source actor', role: 'actor', character: 'Character' }], source: 'nfo', locked: false }
  } };
}
export function editorFake(intercept: (request: Request, path: string) => Response | Promise<Response> | undefined = () => undefined) {
  const calls: { method: string; path: string; body: unknown }[] = [];
  const states: Record<string, MetadataFields> = { i1: metadataFixture('i1'), i2: metadataFixture('i2') };
  const client = clientFor(async (input, init) => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const path = new URL(request.url).pathname.replace('/pleya/v1', '');
    const body = request.method === 'PUT' ? await request.clone().json() as Record<string, unknown> : undefined;
    calls.push({ method: request.method, path, body });
    const held = intercept(request, path); if (held) return held;
    const id = path.split('/')[2]!; const data = states[id]; if (!data) return apiError('library.not_found', 404);
    if (path === `/items/${id}`) return json({ id, title: data.fields.title.value, kind: 'movie', added_at: '2026-11-02T01:00:00Z' } satisfies Item);
    if (request.method === 'PUT') {
      for (const [field, value] of Object.entries(body ?? {})) Object.assign(data.fields[field as keyof typeof data.fields], { value, source: 'manual', locked: true });
    }
    if (request.method === 'DELETE') {
      const field = path.split('/').at(-1)! as keyof typeof data.fields;
      Object.assign(data.fields[field], { source: 'tmdb', locked: false });
    }
    return json(data);
  });
  return { client, states, calls, writes: () => calls.filter(call => call.method !== 'GET') };
}
