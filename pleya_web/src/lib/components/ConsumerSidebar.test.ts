import {fireEvent,render,screen} from '@testing-library/svelte';
import {describe,it,expect} from 'vitest';
import ConsumerSidebar from './ConsumerSidebar.svelte';
import {navItems} from './navItems';
const items=navItems({browse:true},[{id:'films',kind:'movies'},{id:'shows',kind:'shows'},{id:'books',kind:'books'}]);
describe('consumer navigation',()=>{
 it('keeps all permitted destinations and accessible names when collapsed',async()=>{
  render(ConsumerSidebar,{items,activeId:'home',showSearch:true,showFavorites:true,showAdmin:true});
  for(const name of ['Home','Series','Films','Books','My Pleya','Search','Favorites']) expect(screen.getByRole('link',{name})).toBeInTheDocument();
  const toggle=screen.getByRole('button');expect(toggle).toHaveAttribute('aria-expanded','true');await fireEvent.click(toggle);expect(toggle).toHaveAttribute('aria-expanded','false');
  expect(screen.getByRole('link',{name:'Home'})).toHaveAttribute('aria-current','page');
  expect(screen.getByRole('link',{name:'Books'})).toHaveAttribute('href','/libraries/books');
 });
 it('highlights favorites without also marking the parent destination',()=>{
  const {container}=render(ConsumerSidebar,{items,activeId:'my',showFavorites:true,favoritesActive:true});
  expect(screen.getByRole('link',{name:'Favorites'})).toHaveAttribute('aria-current','page');
  expect(screen.getByRole('link',{name:'My Pleya'})).not.toHaveAttribute('aria-current');
  expect(container.querySelectorAll('[aria-current=page]')).toHaveLength(1);
 });
 it('does not expose unsupported search, favorites or administration',()=>{
  render(ConsumerSidebar,{items:navItems(null,[]),activeId:'my'});
  expect(screen.queryByRole('link',{name:'Search'})).toBeNull();
  expect(screen.queryByRole('link',{name:'Favorites'})).toBeNull();
  expect(screen.queryByRole('link',{name:/admin/i})).toBeNull();
  expect(screen.getAllByRole('link')).toHaveLength(2);
 });
});
