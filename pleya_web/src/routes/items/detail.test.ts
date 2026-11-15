import { fireEvent, render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../lib/api/types';
import { ARTWORK_LOADER_KEY } from '../../lib/components/artworkLoader';
const h=vi.hoisted(()=>({goto:vi.fn(),tracks:false,item:vi.fn(),children:vi.fn(),playback:true,personal:false,admin:false,overrides:false,favorite:vi.fn(),preference:vi.fn()}));
vi.mock('$app/navigation',()=>({goto:h.goto}));
vi.mock('$app/state',()=>({page:{params:{id:'movie'},url:new URL('http://client.test/items/movie')}}));
vi.mock('../../lib/stores/session.svelte.js',()=>({session:{client:{item:h.item,children:h.children},get canAdminister(){return h.admin;},get capabilities(){return {playback_plan:h.playback,playback_audio_selection:true,favorites:h.personal,metadata_overrides:h.overrides,track_preferences:h.tracks};}}}));
vi.mock('../../lib/api/personal',()=>({personalApi:()=>({setFavorite:h.favorite,trackPreference:async()=>({source_item_id:null,audio_language:null,subtitle_language:null,subtitle_mode:null,updated_at:null}),setTrackPreference:h.preference})}));
import Detail from './[id]/+page.svelte';
const movie:Item={id:'movie',kind:'movie',title:'Fixture film',added_at:'2026-10-29T12:00:00Z',summary:'A real plot from NFO.',genres:['Science Fiction'],content_rating:'PG',people:[{name:'Director name',role:'director'},{name:'Actor name',role:'actor',character:'Character name'},{name:'Writer name',role:'writer'}],versions:[{id:'first',container:'mkv',edition:'Theatrical',duration_ms:60000,file_count:1},{id:'second',container:'mp4',edition:'Extended',duration_ms:70000,file_count:1}],user_state:{position_ms:12000,watched:false,play_count:0,updated_at:'2026-10-29T12:00:00Z'}};
beforeEach(()=>{h.tracks=false;h.goto.mockReset();h.preference.mockReset().mockResolvedValue({source_item_id:'movie',audio_language:null,subtitle_language:null,subtitle_mode:null,updated_at:null});h.playback=true;h.personal=false;h.admin=false;h.overrides=false;h.favorite.mockReset().mockResolvedValue(undefined);h.item.mockReset();h.children.mockReset();h.item.mockResolvedValue(structuredClone(movie));h.children.mockResolvedValue({items:[],next_cursor:null});});
describe('public detail consumer',()=>{
 it('inherits a validated series backdrop while resume and versions stay on the episode', async()=>{
  h.item.mockImplementation(async id => id === 'movie'
   ? { ...movie, kind:'episode', parent_id:'season', artwork:undefined }
   : id === 'season' ? { id:'season', kind:'season', parent_id:'show', title:'Season 38' }
   : { id:'show', kind:'show', title:'The Simpsons', artwork:{backdrop_id:'show-background',poster_id:'show-poster'} });
  const loader=vi.fn(async()=>new Blob(['image']));
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

it('opens the separate metadata editor from the More actions menu of an authorized movie',async()=>{
 h.admin=true;h.overrides=true;render(Detail);
 await fireEvent.click(await screen.findByRole('button',{name:'More actions'}));
 await fireEvent.click(screen.getByRole('menuitem',{name:'Edit metadata'}));
 expect(h.goto).toHaveBeenCalledWith('/admin/metadata/edit?item=movie');
});

it.each(['role','capability','kind'])('hides the editor without %s eligibility',async reason=>{
 h.admin=reason!=='role';h.overrides=reason!=='capability';
 if(reason==='kind') h.item.mockResolvedValue({...structuredClone(movie),kind:'episode'});
 render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
 expect(screen.queryByRole('link',{name:'Edit metadata'})).toBeNull();
 const menu=screen.queryByRole('button',{name:'More actions'});
 if(reason==='capability'){await fireEvent.click(menu!);expect(screen.queryByRole('menuitem',{name:'Edit metadata'})).toBeNull();expect(screen.getByRole('menuitem',{name:'Correct match'})).toBeInTheDocument();}
 else expect(menu).toBeNull();
});

describe('film detail (C-05)',()=>{
 const tracked={...movie,duration_ms:60000,external_ids:{tmdb:693134},versions:[{...movie.versions![0]!,video_streams:[{id:'v',index:0,codec:'hevc',width:3840,height:1608,bit_depth:10}],audio_streams:[{id:'a-en',index:1,codec:'truehd',language:'eng',is_default:true},{id:'a-nl',index:2,codec:'aac',language:'nld',is_default:false}],subtitle_streams:[{id:'s-nl',index:3,format:'srt' as const,language:'nld',is_default:false,is_forced:false,is_hearing_impaired:false,is_external:true}]}]};
 it('puts duration and the end time computed in the browser on the meta line',async()=>{
  h.item.mockResolvedValue(structuredClone(tracked));render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  const line=screen.getByText(/Science Fiction/);
  expect(line).toHaveTextContent(/^1m · PG · Science Fiction · ends at \d{1,2}:\d{2}/);
  expect(screen.getByRole('progressbar',{name:'Watched 20%'})).toHaveValue(20);
 });
 it('carries the chosen audio and subtitle to the next playback and saves them only with the capability',async()=>{
  h.item.mockResolvedValue(structuredClone(tracked));render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  await fireEvent.change(screen.getByRole('combobox',{name:'Audio'}),{target:{value:'a-nl'}});
  await fireEvent.change(screen.getByRole('combobox',{name:'Subtitles'}),{target:{value:'s-nl'}});
  await vi.waitFor(()=>expect(screen.getByRole('link',{name:/Resume/})).toHaveAttribute('href','/items/movie/play?t=12&version=first&audio=a-nl&subtitle=s-nl'));
  expect(h.preference).not.toHaveBeenCalled();
 });
 it('saves the choice through the track preference route when the server supports it',async()=>{
  h.tracks=true;h.item.mockResolvedValue(structuredClone(tracked));render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  await fireEvent.change(screen.getByRole('combobox',{name:'Audio'}),{target:{value:'a-nl'}});
  await vi.waitFor(()=>expect(h.preference).toHaveBeenCalledWith('movie',{audio_language:'nld'}));
 });
 it('shows cast and crew and the file section with only what the item carries',async()=>{
  h.item.mockResolvedValue(structuredClone(tracked));render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.getByRole('heading',{name:'Cast and crew'})).toBeInTheDocument();
  const file=screen.getByRole('region',{name:'File'});
  expect(file).toHaveTextContent('hevc · 3840×1608 · 10-bit');expect(file).toHaveTextContent('mkv · 1m');expect(file).toHaveTextContent('TMDB 693134');expect(file).toHaveTextContent(/Added/);
  expect(screen.queryByRole('heading',{name:'Versions'})).toBeNull();
 });
 it('has no cast section when the item carries no people',async()=>{
  h.item.mockResolvedValue({...structuredClone(tracked),people:null});render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.queryByRole('heading',{name:'Cast and crew'})).toBeNull();
 });
 it('hides the admin entries from a member',async()=>{
  h.item.mockResolvedValue(structuredClone(tracked));render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.queryByRole('button',{name:'More actions'})).toBeNull();
 });
});

describe('episode detail stays as it was (a series has its own page, see series.test.ts)',()=>{
 const streams={video_streams:[{id:'v',index:0,codec:'hevc'}],audio_streams:[{id:'a-nl',index:2,codec:'aac',language:'nld',is_default:false}]};
 it.each(['episode'] as const)('renders the %s detail without the film-only parts',async kind=>{
  h.admin=true;h.overrides=true;h.tracks=true;
  h.item.mockResolvedValue({...structuredClone(movie),kind,index:3,duration_ms:60000,versions:movie.versions!.map(v=>({...v,...streams}))});
  render(Detail);await screen.findByRole('heading',{name:'Fixture film'});
  expect(screen.getByText(/Science Fiction/)).toHaveTextContent(kind==='episode'?/^Episode 3 · PG · Science Fiction$/:/^PG · Science Fiction$/);
  expect(screen.getByRole('heading',{name:'Versions'})).toBeInTheDocument();
  expect(screen.getByText('Director').tagName).toBe('DT');expect(screen.getByText('Duration').tagName).toBe('DT');
  expect(screen.getByRole('combobox',{name:'Version'})).toBeInTheDocument();
  for(const name of ['Audio','Subtitles']) expect(screen.queryByRole('combobox',{name})).toBeNull();
  for(const name of ['Cast and crew','File']) expect(screen.queryByRole('heading',{name})).toBeNull();
  expect(screen.queryByRole('button',{name:'More actions'})).toBeNull();expect(screen.queryByRole('progressbar')).toBeNull();
  expect(h.preference).not.toHaveBeenCalled();
  expect(screen.getByRole('link',{name:/Resume/})).toHaveAttribute('href','/items/movie/play?t=12&version=first');
 });
});
