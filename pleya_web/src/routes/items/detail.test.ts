import { fireEvent, render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../lib/api/types';
import { ARTWORK_LOADER_KEY } from '../../lib/components/artworkLoader';
const h=vi.hoisted(()=>({item:vi.fn(),children:vi.fn(),playback:true,personal:false,admin:false,overrides:false,collections:false,presentation:false,favorite:vi.fn()}));
vi.mock('$app/state',()=>({page:{params:{id:'movie'},url:new URL('http://client.test/items/movie')}}));
vi.mock('../../lib/stores/session.svelte.js',()=>({session:{client:{item:h.item,children:h.children},get canAdminister(){return h.admin;},get capabilities(){return {playback_plan:h.playback,favorites:h.personal,metadata_overrides:h.overrides,collections:h.collections,detail_presentation:h.presentation};}}}));
vi.mock('../../lib/api/personal',()=>({personalApi:()=>({setFavorite:h.favorite})}));
import Detail from './[id]/+page.svelte';
const movie:Item={id:'movie',kind:'movie',title:'Fixture film',added_at:'2026-10-29T12:00:00Z',summary:'A real plot from NFO.',genres:['Science Fiction'],content_rating:'PG',people:[{name:'Director name',role:'director'},{name:'Actor name',role:'actor',character:'Character name'},{name:'Writer name',role:'writer'}],versions:[{id:'first',container:'mkv',edition:'Theatrical',duration_ms:60000,file_count:1},{id:'second',container:'mp4',edition:'Extended',duration_ms:70000,file_count:1}],user_state:{position_ms:12000,watched:false,play_count:0,updated_at:'2026-10-29T12:00:00Z'}};
beforeEach(()=>{h.playback=true;h.personal=false;h.admin=false;h.overrides=false;h.collections=false;h.presentation=false;h.favorite.mockReset().mockResolvedValue(undefined);h.item.mockReset();h.children.mockReset();h.item.mockResolvedValue(structuredClone(movie));h.children.mockResolvedValue({items:[],next_cursor:null});});
describe('public detail consumer',()=>{
 it('inherits a validated series backdrop while resume and versions stay on the episode', async()=>{
  h.item.mockImplementation(async id => id === 'movie'
   ? { ...movie, kind:'episode', parent_id:'season', artwork:undefined }
   : id === 'season' ? { id:'season', kind:'season', parent_id:'show', title:'Season 38' }
   : { id:'show', kind:'show', title:'The Simpsons', artwork:{backdrop_id:'show-background',poster_id:'show-poster'} });
  const loader=vi.fn(async(_id:string)=>new Blob(['image']));
  render(Detail,{context:new Map([[ARTWORK_LOADER_KEY,loader]])});
  expect(await screen.findByRole('link',{name:'The Simpsons · Season 38'})).toHaveAttribute('href','/items/season');
  expect(screen.getByRole('heading',{name:'Fixture film'})).toBeInTheDocument();
  expect(screen.getByRole('link',{name:/Resume/})).toHaveAttribute('href','/items/movie/play?t=12&version=first');
  expect(loader.mock.calls.length).toBeGreaterThan(0);
 });
 it('loads the actual poster for the poster slot even when a backdrop exists', async()=>{
  h.item.mockResolvedValue({...movie,artwork:{poster_id:'portrait',backdrop_id:'landscape'}});
  const loader=vi.fn(async(_id:string)=>new Blob(['image']));
  render(Detail,{context:new Map([[ARTWORK_LOADER_KEY,loader]])});
  await screen.findByRole('heading',{name:'Fixture film'});
  await vi.waitFor(()=>expect(loader.mock.calls.map(call=>call[0])).toContain('portrait'));
 });
 it('shows existing metadata without invented person navigation',async()=>{
  render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.getByText('A real plot from NFO.')).toBeInTheDocument();
  expect(screen.getByText(/Science Fiction/)).toBeInTheDocument();
  expect(screen.getByText(/\bPG\b/)).toBeInTheDocument();
  expect(screen.getByText('Director name')).toBeInTheDocument();
  expect(screen.getByText('Actor name').parentElement).toHaveTextContent('Character name');
  expect(screen.getByText('Actor name').closest('a')).toBeNull();
 });
 it('preserves the selected stable version ID in resume and play-from-start links',async()=>{
  render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  await fireEvent.change(screen.getByRole('combobox',{name:'Version'}),{target:{value:'second'}});
  expect(screen.getByRole('link',{name:/Resume/})).toHaveAttribute('href','/items/movie/play?t=12&version=second');
  expect(screen.getByRole('link',{name:'Play from start'})).toHaveAttribute('href','/items/movie/play?version=second');
 });
 it('keeps later seasons reachable through the existing cursor',async()=>{
  h.item.mockResolvedValue({...movie,kind:'show',versions:undefined});
  h.children.mockResolvedValueOnce({items:[{id:'s1',kind:'season',title:'Season one',added_at:movie.added_at}],next_cursor:'next-page'}).mockResolvedValueOnce({items:[{id:'s2',kind:'season',title:'Season two',added_at:movie.added_at}],next_cursor:null});
  render(Detail);await screen.findByRole('link',{name:/Season one/});
  await fireEvent.click(screen.getByRole('button',{name:'Load more'}));
  await screen.findByRole('link',{name:/Season two/});
  expect(h.children).toHaveBeenLastCalledWith('movie',{limit:100,cursor:'next-page'},expect.any(AbortSignal));
 });
 it('retains metadata when loading seasons fails and retries only the failed section',async()=>{
  h.item.mockResolvedValue({...movie,kind:'show',versions:undefined});
  h.children.mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce({items:[{id:'s1',kind:'season',title:'Season one',added_at:movie.added_at}],next_cursor:null});
  render(Detail);await screen.findByRole('button',{name:'Retry'});
  expect(screen.getByText('A real plot from NFO.')).toBeInTheDocument();
  await fireEvent.click(screen.getByRole('button',{name:'Retry'}));
  await screen.findByRole('link',{name:/Season one/});expect(h.item).toHaveBeenCalledTimes(1);
 });
 it('omits absent metadata blocks and unsupported playback actions on an older server',async()=>{
  h.playback=false;h.item.mockResolvedValue({...movie,summary:undefined,genres:undefined,people:undefined,content_rating:undefined});
  render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.queryByRole('link',{name:/Resume/})).toBeNull();
  expect(screen.queryByText('Cast')).toBeNull();
  expect(screen.queryByText('Director')).toBeNull();
 });
 it('connects the actual detail favorite control and keeps the selected version',async()=>{
  h.personal=true;render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  await fireEvent.change(screen.getByRole('combobox',{name:'Version'}),{target:{value:'second'}});
  await fireEvent.click(screen.getByRole('button',{name:'Add to favorites'}));
  await screen.findByRole('button',{name:'Remove from favorites'});expect(h.favorite).toHaveBeenCalledWith('movie',true);
  expect(screen.getByRole('link',{name:'Play from start'})).toHaveAttribute('href','/items/movie/play?version=second');
 });

});

it('opens the separate metadata editor from an authorized movie',async()=>{
 h.admin=true;h.overrides=true;render(Detail);
 expect(await screen.findByRole('link',{name:'Edit metadata'})).toHaveAttribute('href','/admin/metadata/edit?item=movie');
});

it.each(['role','capability','kind'])('hides the editor without %s eligibility',async reason=>{
 h.admin=reason!=='role';h.overrides=reason!=='capability';
 if(reason==='kind') h.item.mockResolvedValue({...structuredClone(movie),kind:'episode'});
 render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
 expect(screen.queryByRole('link',{name:'Edit metadata'})).toBeNull();
});

it('opens the same separate editor for a series',async()=>{
 h.admin=true;h.overrides=true;h.item.mockResolvedValue({...structuredClone(movie),kind:'show'});
 render(Detail);expect(await screen.findByRole('link',{name:'Edit metadata'})).toHaveAttribute('href','/admin/metadata/edit?item=movie');
});


it('places cast outside the hero and preserves its character metadata', async () => {
 render(Detail);
 const name = await screen.findByText('Actor name');
 expect(name.closest('header')).toBeNull();
 expect(name.closest('section')).toHaveAccessibleName('Cast and crew');
 expect(name.parentElement).toHaveTextContent('Character name');
});

it('places seasons immediately after the series hero, ahead of cast', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),kind:'show',versions:undefined});
 render(Detail);
 await screen.findByRole('heading',{name:'Fixture film'});
 const seasons = screen.getByRole('heading',{name:'Seasons'}).closest('section');
 expect(screen.getByRole('link',{name:'View seasons'})).toHaveAttribute('href','#detail-children');
 expect(seasons?.previousElementSibling?.tagName).toBe('HEADER');
 expect(seasons?.nextElementSibling).toContainElement(screen.getByText('Actor name'));
});

it('retains Add to list when collections is the only personal capability', async () => {
 h.collections=true;
 render(Detail);
 await screen.findByRole('heading',{name:'Fixture film'});
 expect(screen.getByRole('button',{name:'Add to'})).toBeInTheDocument();
 expect(screen.queryByRole('button',{name:'Add to favorites'})).toBeNull();
});


it('keeps seasons in the series page and restores each season pager', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),kind:'show',versions:undefined});
 const seasons = ['s1','s2'].map((id,i)=>({id,kind:'season',title:`Season ${i+1}`,added_at:movie.added_at}));
 h.children.mockImplementation(async (id) => ({items:id==='movie'?seasons:[{id:`ep-${id}`,kind:'episode',title:`Episode ${id}`,added_at:movie.added_at}],next_cursor:null}));
 render(Detail);
 const first = await screen.findByRole('tab',{name:'Season 1'});
 await fireEvent.click(first);
 await screen.findByRole('link',{name:/Episode s1/});
 expect(first).toHaveAttribute('aria-selected','true');
 expect(screen.getByRole('heading',{level:1})).toHaveTextContent('Fixture film');
 await fireEvent.click(screen.getByRole('tab',{name:'Season 2'}));
 await screen.findByRole('link',{name:/Episode s2/});
 expect(screen.queryByRole('link',{name:/Episode s1/})).toBeNull();
 await fireEvent.click(first);
 await screen.findByRole('link',{name:/Episode s1/});
 expect(h.children.mock.calls.filter(call=>call[0]==='s1')).toHaveLength(1);
 await fireEvent.keyDown(first,{key:'ArrowLeft'});
 expect(screen.getByRole('tab',{name:'Series'})).toHaveAttribute('aria-selected','true');
 expect(screen.getByRole('link',{name:/Season 1/})).toBeInTheDocument();
});

it('keeps failed season loads retryable without reloading the series or losing its tabs', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),kind:'show',versions:undefined});
 h.children.mockResolvedValueOnce({items:[{id:'s1',kind:'season',title:'Season 1',added_at:movie.added_at}],next_cursor:null})
  .mockRejectedValueOnce(new Error('offline'))
  .mockResolvedValueOnce({items:[{id:'ep1',kind:'episode',title:'Recovered episode',added_at:movie.added_at}],next_cursor:null});
 render(Detail);
 await fireEvent.click(await screen.findByRole('tab',{name:'Season 1'}));
 await fireEvent.click(await screen.findByRole('button',{name:'Retry'}));
 await screen.findByRole('link',{name:/Recovered episode/});
 expect(screen.getByRole('tab',{name:'Season 1'})).toHaveAttribute('aria-selected','true');
 expect(h.item).toHaveBeenCalledTimes(1);
 expect(h.children).toHaveBeenLastCalledWith('s1',{limit:100},expect.any(AbortSignal));
});

it('does not display a late season response over the newly selected season', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),kind:'show',versions:undefined});
 let finishFirst!: (value: unknown) => void;
 h.children.mockResolvedValueOnce({items:['s1','s2'].map((id,i)=>({id,kind:'season',title:`Season ${i+1}`,added_at:movie.added_at})),next_cursor:null})
  .mockImplementationOnce(()=>new Promise(resolve=>{finishFirst=resolve;}))
  .mockResolvedValueOnce({items:[{id:'ep2',kind:'episode',title:'Second season episode',added_at:movie.added_at}],next_cursor:null});
 render(Detail);
 await fireEvent.click(await screen.findByRole('tab',{name:'Season 1'}));
 await fireEvent.click(screen.getByRole('tab',{name:'Season 2'}));
 await screen.findByRole('link',{name:/Second season episode/});
 finishFirst({items:[{id:'ep1',kind:'episode',title:'Late first season episode',added_at:movie.added_at}],next_cursor:null});
 await vi.waitFor(()=>expect(screen.queryByRole('link',{name:/Late first season/})).toBeNull());
 expect(screen.getByRole('tab',{name:'Season 2'})).toHaveAttribute('aria-selected','true');
});


it('transfers keyboard focus from a disappearing season card to its selected tab', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),kind:'show',versions:undefined});
 h.children.mockResolvedValueOnce({items:[{id:'s1',kind:'season',title:'Season 1',added_at:movie.added_at}],next_cursor:null})
  .mockResolvedValueOnce({items:[{id:'ep1',kind:'episode',title:'First episode',added_at:movie.added_at}],next_cursor:null});
 render(Detail);
 const card=await screen.findByRole('link',{name:/^Season 1/});
 card.focus();
 await fireEvent.click(card,{button:0});
 await screen.findByRole('link',{name:/First episode/});
 await vi.waitFor(()=>expect(screen.getByRole('tab',{name:'Season 1'})).toHaveFocus());
});


it('renders only supported actual logo, portrait and source score data, including a real zero', async () => {
 h.presentation=true;
 h.item.mockResolvedValue({...structuredClone(movie),artwork:{logo_id:'actual-logo'},people:[{name:'Actual actor',role:'actor',portrait_id:'actual-portrait'}],external_ratings:[{source:'tmdb',value:0,max_value:10,vote_count:4},{source:'future',value:73,max_value:100},{source:'invented',value:20,max_value:10},null]});
 const loader=vi.fn(async(_id:string)=>new Blob(['image']));
 render(Detail,{context:new Map([[ARTWORK_LOADER_KEY,loader]])});
 await screen.findByRole('heading',{level:1,name:'Fixture film'});
 expect(screen.getByRole('list',{name:'External ratings'})).toHaveTextContent('TMDB0/10');
 expect(screen.getByRole('list',{name:'External ratings'})).toHaveTextContent('FUTURE73/100');
 expect(screen.queryByText('INVENTED')).toBeNull();
 await vi.waitFor(()=>expect(loader.mock.calls.map(call=>call[0])).toEqual(expect.arrayContaining(['actual-logo','actual-portrait'])));
});

it('keeps the real title and names on servers without detail_presentation', async () => {
 h.item.mockResolvedValue({...structuredClone(movie),artwork:{logo_id:'unsupported-logo'},people:[{name:'Actual actor',role:'actor',portrait_id:'unsupported-portrait'}],external_ratings:[{source:'tmdb',value:8,max_value:10}]});
 const loader=vi.fn(async(_id:string)=>new Blob(['image']));
 render(Detail,{context:new Map([[ARTWORK_LOADER_KEY,loader]])});
 await screen.findByRole('heading',{level:1,name:'Fixture film'});
 expect(screen.getByText('Actual actor')).toBeInTheDocument();
 expect(screen.queryByRole('list',{name:'External ratings'})).toBeNull();
 expect(loader).not.toHaveBeenCalled();
});
