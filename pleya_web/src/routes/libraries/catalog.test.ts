import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ items: vi.fn(), facets: vi.fn(), filters: true, watch: true, url: new URL('http://client.test/libraries/lib'), goto: vi.fn() }));
vi.mock('$app/state', () => ({ page: { params: {id:'lib'}, get url() {return h.url;}, state: {} } }));
vi.mock('$app/navigation', () => ({goto: h.goto}));
vi.mock('../../lib/stores/session.svelte.js', () => ({ session: {
  library: () => ({id:'lib',title:'Films',kind:'movies'}),
  get capabilities() { return {filters:h.filters,watch_state:h.watch}; },
  client: {libraryItems:h.items, libraryFacets:h.facets}
} }));
import Catalog from './[id]/+page.svelte';
beforeEach(() => {
  vi.stubGlobal('matchMedia',()=>({matches:true}));
  h.filters=true; h.watch=true; h.url=new URL('http://client.test/libraries/lib');
  h.goto.mockReset(); h.items.mockReset(); h.facets.mockReset();
  h.items.mockResolvedValue({items:[],next_cursor:null});
  h.facets.mockResolvedValue({genres:[],years:[],resolutions:[],audio_languages:[],content_ratings:[],watch:{unwatched:0,in_progress:0,watched:0}});
});
describe('public library catalog', () => {
  it('consumes deep-linked filters and the complete server sort contract', async () => {
    h.url=new URL('http://client.test/libraries/lib?genre=Drama&year=2025&watch=unwatched&resolution=fhd&sort=-duration');
    render(Catalog);
    await waitFor(() => expect(h.items).toHaveBeenCalledWith('lib',expect.objectContaining({genre:['Drama'],year:['2025'],watch:'unwatched',resolution:['fhd'],sort:'-duration'}),expect.any(AbortSignal)));
    expect(h.facets).toHaveBeenCalledWith('lib',expect.any(AbortSignal));
    expect(await screen.findByText('No titles match these filters.')).toBeInTheDocument();
    expect(screen.getByRole('combobox',{name:'Sort'}).querySelectorAll('option')).toHaveLength(10);
  });
  it('uses only legacy requests and sort choices on an old server', async () => {
    h.filters=false; render(Catalog);
    await waitFor(() => expect(h.items).toHaveBeenCalled());
    expect(h.facets).not.toHaveBeenCalled();
    expect(screen.queryByRole('button',{name:'Filters'})).toBeNull();
    expect(screen.getByRole('combobox',{name:'Sort'}).querySelectorAll('option')).toHaveLength(6);
  });
  it.each(['watch=unwatched','sort=-duration','year=bad'])('does not silently ignore an unsupported link: %s', async query => {
    h.filters=false; h.url=new URL('http://client.test/libraries/lib?'+query); render(Catalog);
    expect(await screen.findByRole('button',{name:'Clear filters'})).toBeInTheDocument();
    expect(h.items).not.toHaveBeenCalled(); expect(h.facets).not.toHaveBeenCalled();
  });
  it('blocks watch filters when watch state is unavailable', async () => {
    h.watch=false; h.url=new URL('http://client.test/libraries/lib?watch=watched'); render(Catalog);
    expect(await screen.findByRole('button',{name:'Clear filters'})).toBeInTheDocument();
    expect(h.items).not.toHaveBeenCalled();
  });
});
