import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item, Library } from '../api/types';
const h=vi.hoisted(()=>({items:vi.fn(),facets:vi.fn(),hub:vi.fn(),filters:true,watch:true,libraries:[] as Library[]}));
vi.mock('../stores/session.svelte.js',()=>({session:{
 get libraries(){return h.libraries;}, get capabilities(){return {browse:true,filters:h.filters,watch_state:h.watch};},
 client:{libraryItems:h.items,libraryFacets:h.facets,hub:h.hub}
}}));
import VideoLanding from './VideoLanding.svelte';
const item=(id:string,kind:Item['kind']='movie'):Item=>({id,kind,title:id,added_at:'2026-10-29T12:00:00Z'});
beforeEach(()=>{
 h.filters=true;h.watch=true;
 h.libraries=[{id:'film',title:'Movies',kind:'movies',item_count:2},{id:'kids',title:'Kids',kind:'movies',item_count:1},{id:'tv',title:'TV',kind:'shows',item_count:1}];
 h.items.mockReset();h.facets.mockReset();h.hub.mockReset();
 h.items.mockImplementation(async(id,q)=>({items:[item(`${id}-${q.watch??q.genre?.[0]??'recent'}`)],next_cursor:null}));
 h.facets.mockResolvedValue({genres:[{value:'Drama',count:2}],years:[],resolutions:[],audio_languages:[],content_ratings:[],watch:{unwatched:1,in_progress:0,watched:1}});
 h.hub.mockImplementation(async(id)=>({items:[item(id,'episode')]}));
});
describe('video kind landings',()=>{
 it('keeps all libraries and links filter rows to the existing catalog',async()=>{
  render(VideoLanding,{props:{kind:'movies'}});
  expect(await screen.findByRole('heading',{name:'Recently added · Movies'})).toBeInTheDocument();
  expect(screen.getByRole('heading',{name:'Recently added · Kids'})).toBeInTheDocument();
  expect(screen.queryByRole('heading',{name:'Recently added · TV'})).toBeNull();
  expect(screen.getByRole('heading',{name:'Films',level:1})).toBeInTheDocument();
  expect(screen.getByRole('link',{name:/All films/})).toHaveAttribute('href','/libraries?kind=movies');
  expect(document.querySelector('a[href="/libraries/film?watch=unwatched&sort=-added_at"]')).not.toBeNull();
  expect(h.items).toHaveBeenCalledWith('film',expect.objectContaining({genre:['Drama']}),expect.any(AbortSignal));
  expect(h.hub).not.toHaveBeenCalled();
  expect(screen.queryByText('Continue watching')).toBeNull();
 });
 it('shows next and new episodes before series rows',async()=>{
  render(VideoLanding,{props:{kind:'shows'}});
  expect(await screen.findByRole('heading',{name:'Next episodes'})).toBeInTheDocument();
  expect(h.hub).toHaveBeenCalledWith('next_up',{library_id:'tv',limit:24},expect.any(AbortSignal));
  expect(h.hub).toHaveBeenCalledWith('recently_added',{library_id:'tv',limit:24},expect.any(AbortSignal));
  expect(screen.getAllByRole('heading',{level:2})[0]).toHaveTextContent('Next episodes');
  expect(screen.getByRole('link',{name:/All series/})).toHaveAttribute('href','/libraries/tv');
 });
 it('does not call filters or watch routes on an older server',async()=>{
  h.filters=false;h.watch=false;render(VideoLanding,{props:{kind:'movies'}});
  await screen.findByRole('heading',{name:'Recently added · Movies'});
  expect(h.facets).not.toHaveBeenCalled();expect(h.hub).not.toHaveBeenCalled();
  expect(h.items.mock.calls.every(([,q])=>!q.watch&&!q.genre)).toBe(true);
 });
 it('bounds genre previews to the three largest populated facets',async()=>{
  h.libraries=h.libraries.slice(0,1);
  h.facets.mockResolvedValue({genres:[{value:'Empty',count:0},{value:'Fourth',count:1},{value:'Third',count:2},{value:'Second',count:3},{value:'First',count:4}]});
  render(VideoLanding,{props:{kind:'movies'}});
  await screen.findByRole('heading',{name:'Recently added'});
  expect(h.items.mock.calls.filter(([,q])=>q.genre).map(([,q])=>q.genre[0])).toEqual(['First','Second','Third']);
  expect(screen.queryByRole('heading',{name:'Fourth'})).toBeNull();
 });
 it('has a safe escape when this kind has no library',async()=>{
  h.libraries=[];render(VideoLanding,{props:{kind:'shows'}});
  await screen.findByRole('heading',{name:'Nothing has been added yet'});
  expect(screen.queryByRole('link',{name:/All series/})).toBeNull();
  expect(screen.getByRole('link',{name:'Go to My Pleya'})).toHaveAttribute('href','/server');
  expect(h.items).not.toHaveBeenCalled();expect(h.facets).not.toHaveBeenCalled();
 });
 it('hides empty preview rows and aborts requests on departure' ,async()=>{
  h.items.mockResolvedValue({items:[],next_cursor:null});h.facets.mockResolvedValue({genres:[]});
  const {unmount}=render(VideoLanding,{props:{kind:'movies'}});
  await waitFor(()=>expect(h.items).toHaveBeenCalled());
  unmount();expect(h.items.mock.calls.every((call)=>call[2].aborted)).toBe(true);
 });
});
