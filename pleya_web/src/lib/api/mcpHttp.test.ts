import { describe, expect, it } from 'vitest';
import { PleyaClient } from './client';
import { TokenStore } from '../auth/tokens';
import { memoryStorage } from '../admin/libraryFake';

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });

function tokens() {
  const store = new TokenStore(memoryStorage(), memoryStorage());
  store.set({ access_token: 'fixture-access-a', refresh_token: 'fixture-refresh-a', expires_in_ms: 900000 });
  return store;
}

describe('MCP via dezelfde HTTP-identiteit', () => {
  it('bewaart het subpad en vernieuwt een verlopen bearer met behoud van de RPC-body', async () => {
    const seen: { token: string | null; body: string }[] = [];
    const client = new PleyaClient({ baseUrl: 'http://server.test/prefix/pleya/v1', tokens: tokens(), fetch: async (input, init) => {
      const request = input instanceof Request ? input : new Request(String(input), init);
      if (new URL(request.url).pathname.endsWith('/auth/refresh')) return json({ access_token: 'fixture-access-b', refresh_token: 'fixture-refresh-b', expires_in_ms: 900000 });
      expect(new URL(request.url).pathname).toBe('/prefix/mcp');
      seen.push({ token: request.headers.get('Authorization'), body: await request.text() });
      return seen.length === 1 ? json({ error: { code: 'auth.token_expired' } }, 401) : json({ result: { tools: [{ name: 'listLibraries' }] } });
    } });
    expect(await client.mcpTools()).toEqual([{ name: 'listLibraries' }]);
    expect(seen.map((r) => r.token)).toEqual(['Bearer fixture-access-a', 'Bearer fixture-access-b']);
    expect(seen[0]?.body).toBe(seen[1]?.body);
  });

  it('geeft een laat register niet terug nadat het account afmeldt', async () => {
    let respond!: (response: Response) => void;
    const response = new Promise<Response>((resolve) => { respond = resolve; });
    const client = new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens: tokens(), fetch: () => response });
    const pending = client.mcpTools();
    await client.signOut();
    respond(json({ result: { tools: [{ name: 'private-old-account' }] } }));
    await expect(pending).rejects.toThrow();
  });

  it('weigert een ongeldig register zonder de pagina te laten crashen', async () => {
    const client = new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens: tokens(), fetch: async () => json({ result: { tools: [{ name: 42 }] } }) });
    await expect(client.mcpTools()).rejects.toThrow();
  });
});
