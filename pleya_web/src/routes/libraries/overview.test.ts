import { render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
vi.mock('$app/state',()=>({page:{url:new URL('http://client.test/libraries?kind=movies')}}));
vi.mock('../../lib/stores/session.svelte.js',()=>({session:{libraries:[{id:'film',title:'Movies',kind:'movies',item_count:2},{id:'kids',title:'Kids',kind:'movies',item_count:1},{id:'tv',title:'TV',kind:'shows',item_count:1}]}}));
import Libraries from './+page.svelte';
describe('landing library selector',()=>{
 it('retains every library of the requested kind without mixing in other kinds',()=>{
  render(Libraries);
  expect(screen.getByRole('link',{name:/Movies/})).toHaveAttribute('href','/libraries/film');
  expect(screen.getByRole('link',{name:/Kids/})).toHaveAttribute('href','/libraries/kids');
  expect(screen.queryByRole('link',{name:/TV/})).toBeNull();
 });
});
