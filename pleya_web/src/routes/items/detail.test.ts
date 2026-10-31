import { fireEvent, render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../lib/api/types';
const h=vi.hoisted(()=>({item:vi.fn(),children:vi.fn(),playback:true,personal:false,favorite:vi.fn()}));
vi.mock('$app/state',()=>({page:{params:{id:'movie'},url:new URL('http://client.test/items/movie')}}));
vi.mock('../../lib/stores/session.svelte.js',()=>({session:{client:{item:h.item,children:h.children},get capabilities(){return {playback_plan:h.playback,favorites:h.personal};}}}));
vi.mock('../../lib/api/personal',()=>({personalApi:()=>({setFavorite:h.favorite})}));
import Detail from './[id]/+page.svelte';
const movie:Item={id:'movie',kind:'movie',title:'Fixture film',added_at:'2026-10-29T12:00:00Z',summary:'A real plot from NFO.',genres:['Science Fiction'],content_rating:'PG',people:[{name:'Director name',role:'director'},{name:'Actor name',role:'actor',character:'Character name'},{name:'Writer name',role:'writer'}],versions:[{id:'first',container:'mkv',edition:'Theatrical',duration_ms:60000,file_count:1},{id:'second',container:'mp4',edition:'Extended',duration_ms:70000,file_count:1}],user_state:{position_ms:12000,watched:false,play_count:0,updated_at:'2026-10-29T12:00:00Z'}};
beforeEach(()=>{h.playback=true;h.personal=false;h.favorite.mockReset().mockResolvedValue(undefined);h.item.mockReset();h.children.mockReset();h.item.mockResolvedValue(structuredClone(movie));h.children.mockResolvedValue({items:[],next_cursor:null});});
describe('public detail consumer',()=>{
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
  render(Detail);await screen.findByText('Season one');
  await fireEvent.click(screen.getByRole('button',{name:'Load more'}));
  await screen.findByText('Season two');
  expect(h.children).toHaveBeenLastCalledWith('movie',{limit:100,cursor:'next-page'},expect.any(AbortSignal));
 });
 it('retains metadata when loading seasons fails and retries only the failed section',async()=>{
  h.item.mockResolvedValue({...movie,kind:'show',versions:undefined});
  h.children.mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce({items:[{id:'s1',kind:'season',title:'Season one',added_at:movie.added_at}],next_cursor:null});
  render(Detail);await screen.findByRole('button',{name:'Retry'});
  expect(screen.getByText('A real plot from NFO.')).toBeInTheDocument();
  await fireEvent.click(screen.getByRole('button',{name:'Retry'}));
  await screen.findByText('Season one');expect(h.item).toHaveBeenCalledTimes(1);
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
