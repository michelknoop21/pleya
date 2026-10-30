import { fireEvent,render,screen,waitFor,within } from '@testing-library/svelte';
import { beforeEach,describe,expect,it,vi } from 'vitest';
import type { Item } from '../api/types';
const h=vi.hoisted(()=>({favorite:vi.fn(),rating:vi.fn(),watched:vi.fn(),caps:{favorites:true,ratings:true,watch_state:true}}));
vi.mock('../stores/session.svelte.js',()=>({session:{client:{},get capabilities(){return h.caps;}}}));
vi.mock('../api/personal',()=>({personalApi:()=>({setFavorite:h.favorite,setRating:h.rating,setWatched:h.watched})}));
import ItemPersonalActions from './ItemPersonalActions.svelte';
const item:Item={id:'movie',kind:'movie',title:'Movie',added_at:'2026-10-30T00:00:00Z',duration_ms:60000,favorite:false,rating:null};
beforeEach(()=>{h.caps={favorites:true,ratings:true,watch_state:true};h.favorite.mockReset().mockResolvedValue(undefined);h.rating.mockReset().mockResolvedValue(undefined);h.watched.mockReset().mockResolvedValue({position_ms:0,watched:true,play_count:1,updated_at:'2026-10-30T00:00:00Z'});});
describe('public personal item controls',()=>{
 it('updates a favorite only after the server accepts it and ignores duplicate clicks',async()=>{
  let resolve!:()=>void;h.favorite.mockImplementationOnce(()=>new Promise<void>(done=>resolve=done));
  const onchange=vi.fn();render(ItemPersonalActions,{props:{item,onchange}});
  const favorite=screen.getByRole('button',{name:'Add to favorites'});
  await fireEvent.click(favorite);await fireEvent.click(favorite);
  expect(h.favorite).toHaveBeenCalledTimes(1);expect(onchange).not.toHaveBeenCalled();expect(favorite).toBeDisabled();
  resolve();await waitFor(()=>expect(onchange).toHaveBeenCalledWith(expect.objectContaining({id:'movie',favorite:true})));
 });
 it('retains the current state and reports a rejected favorite',async()=>{
  h.favorite.mockRejectedValueOnce(new Error('offline'));const onchange=vi.fn();render(ItemPersonalActions,{props:{item,onchange}});
  await fireEvent.click(screen.getByRole('button',{name:'Add to favorites'}));
  expect(await screen.findByRole('alert')).toBeInTheDocument();expect(onchange).not.toHaveBeenCalled();
  expect(screen.getByRole('button',{name:'Add to favorites'})).toHaveAttribute('aria-pressed','false');
 });
 it('keeps the rating draft local until Save and clears through the same public action',async()=>{
  const onchange=vi.fn();const {rerender}=render(ItemPersonalActions,{props:{item,onchange}});
  await fireEvent.click(screen.getByRole('button',{name:'Rate'}));
  const dialog=await screen.findByRole('dialog',{name:'Your rating'});
  await fireEvent.change(within(dialog).getByRole('combobox',{name:'Rating'}),{target:{value:'7'}});
  expect(h.rating).not.toHaveBeenCalled();await fireEvent.click(within(dialog).getByRole('button',{name:'Save'}));
  await waitFor(()=>expect(onchange).toHaveBeenCalledWith(expect.objectContaining({rating:7})));expect(h.rating).toHaveBeenCalledWith('movie',7);
  await rerender({item:{...item,rating:7}});await fireEvent.click(screen.getByRole('button',{name:'Your rating: 7/10'}));
  const clear=await screen.findByRole('dialog',{name:'Your rating'});
  await fireEvent.change(within(clear).getByRole('combobox',{name:'Rating'}),{target:{value:''}});
  await fireEvent.click(within(clear).getByRole('button',{name:'Save'}));await waitFor(()=>expect(h.rating).toHaveBeenLastCalledWith('movie',null));
 });
 it('marks a movie watched without starting playback',async()=>{
  const onchange=vi.fn();render(ItemPersonalActions,{props:{item,onchange}});
  await fireEvent.click(screen.getByRole('button',{name:'Mark watched'}));
  await waitFor(()=>expect(onchange).toHaveBeenCalledWith(expect.objectContaining({user_state:expect.objectContaining({watched:true})})));
  expect(h.watched).toHaveBeenCalledWith('movie',true,60000);
 });
 it('has no unsupported actions or requests on an older server',()=>{
  h.caps={favorites:false,ratings:false,watch_state:false};render(ItemPersonalActions,{props:{item,onchange:vi.fn()}});
  expect(screen.queryByRole('button')).toBeNull();expect(h.favorite).not.toHaveBeenCalled();expect(h.rating).not.toHaveBeenCalled();expect(h.watched).not.toHaveBeenCalled();
 });
 it('does not publish a late result after this route is left',async()=>{
  let resolve!:()=>void;h.favorite.mockImplementationOnce(()=>new Promise<void>(done=>resolve=done));const onchange=vi.fn();const {unmount}=render(ItemPersonalActions,{props:{item,onchange}});
  await fireEvent.click(screen.getByRole('button',{name:'Add to favorites'}));unmount();resolve();await Promise.resolve();await Promise.resolve();expect(onchange).not.toHaveBeenCalled();
 });
});
