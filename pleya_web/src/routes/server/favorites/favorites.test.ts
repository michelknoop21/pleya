import {fireEvent,render,screen} from '@testing-library/svelte';
import {beforeEach,describe,expect,it,vi} from 'vitest';
const h=vi.hoisted(()=>({favorites:vi.fn(),allowed:true}));
vi.mock('../../../lib/stores/session.svelte.js',()=>({session:{client:{},get capabilities(){return {favorites:h.allowed};}}}));
vi.mock('../../../lib/api/personal',()=>({personalApi:()=>({favorites:h.favorites})}));
import Favorites from './+page.svelte';
const item=(id:string,title:string)=>({id,title,kind:'movie',added_at:'2026-10-30T00:00:00Z'});
beforeEach(()=>{h.allowed=true;h.favorites.mockReset().mockResolvedValue({items:[],next_cursor:null});});
describe('personal favorites route',()=>{
 it('loads every cursor page through the existing personal source',async()=>{
  h.favorites.mockResolvedValueOnce({items:[item('one','First favorite')],next_cursor:'next'}).mockResolvedValueOnce({items:[item('two','Second favorite')],next_cursor:null});
  render(Favorites);await screen.findByText('First favorite');await fireEvent.click(screen.getByRole('button',{name:'Load more'}));await screen.findByText('Second favorite');
  expect(h.favorites).toHaveBeenLastCalledWith({limit:48,cursor:'next'},expect.any(AbortSignal));expect(screen.queryByRole('button',{name:'Load more'})).toBeNull();
 });
 it('shows an honest empty state and link back to My Pleya',async()=>{
  render(Favorites);await screen.findByText('No favorites yet');expect(screen.getByRole('link',{name:'My Pleya'})).toHaveAttribute('href','/server');
 });
 it('retains the first page after a failure and retries the failed cursor',async()=>{
  h.favorites.mockResolvedValueOnce({items:[item('one','First favorite')],next_cursor:'next'}).mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce({items:[item('two','Second favorite')],next_cursor:null});
  render(Favorites);await screen.findByText('First favorite');await fireEvent.click(screen.getByRole('button',{name:'Load more'}));await screen.findByRole('button',{name:'Retry'});expect(screen.getByText('First favorite')).toBeInTheDocument();await fireEvent.click(screen.getByRole('button',{name:'Retry'}));await screen.findByText('Second favorite');
 });
 it('makes no unsupported request on an older server',()=>{
  h.allowed=false;render(Favorites);expect(h.favorites).not.toHaveBeenCalled();expect(screen.getByRole('link',{name:'My Pleya'})).toHaveAttribute('href','/server');
 });
});
