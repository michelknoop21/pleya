import { fireEvent, render, screen, within } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import CatalogFilterBar from './CatalogFilterBar.svelte';
import type { Facets } from '../api/types';

const facets: Facets = {
  genres: [{value:'Drama',count:2},{value:'Comedy',count:1}],
  years: [{value:'2025',count:2}], content_ratings: [{value:'16',count:1}], audio_languages: [{value:'nld',count:1}],
  resolutions: [{value:'fhd',count:2},{value:'future',count:1}],
  watch: {unwatched:2,in_progress:1,watched:1}
};

describe('catalog filter controls', () => {
  it('opens one group at a time and applies a choice immediately', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{year:['2025']},onapply:apply}});
    const genre=screen.getByRole('button',{name:'Genre'});
    expect(genre).toHaveAttribute('aria-expanded','false');
    await fireEvent.click(genre);
    expect(genre).toHaveAttribute('aria-expanded','true');
    await fireEvent.click(within(screen.getByRole('group',{name:'Genre'})).getByRole('button',{name:/^Drama/}));
    expect(apply).toHaveBeenCalledWith({year:['2025'],genre:['Drama']});
    await fireEvent.click(screen.getByRole('button',{name:'Quality'}));
    expect(screen.queryByRole('group',{name:'Genre'})).toBeNull();
    expect(within(screen.getByRole('group',{name:'Quality'})).getByRole('button',{name:/future/})).toBeDisabled();
  });
  it('offers audio language and content rating from the facets', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{},onapply:apply}});
    await fireEvent.click(screen.getByRole('button',{name:'Audio'}));
    await fireEvent.click(within(screen.getByRole('group',{name:'Audio'})).getByRole('button',{name:/Dutch/}));
    expect(apply).toHaveBeenCalledWith({audio_language:['nld']});
    await fireEvent.click(screen.getByRole('button',{name:'Rating'}));
    await fireEvent.click(within(screen.getByRole('group',{name:'Rating'})).getByRole('button',{name:/^16/}));
    expect(apply).toHaveBeenLastCalledWith({content_rating:['16']});
  });
  it('closes the open group on Escape and returns focus to its pill', async () => {
    render(CatalogFilterBar,{props:{facets,filters:{},onapply:vi.fn()}});
    const genre=screen.getByRole('button',{name:'Genre'});
    await fireEvent.click(genre);
    await fireEvent.keyDown(window,{key:'Escape'});
    expect(screen.queryByRole('group',{name:'Genre'})).toBeNull();
    expect(genre).toHaveFocus();
  });
  it('switches the watch state with direct pills', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{genre:['Drama'],watch:'unwatched'},watchState:true,onapply:apply}});
    const watch=screen.getByRole('group',{name:'Watch status'});
    expect(within(watch).getByRole('button',{name:'Not watched'})).toHaveAttribute('aria-pressed','true');
    await fireEvent.click(within(watch).getByRole('button',{name:'Watched'}));
    expect(apply).toHaveBeenCalledWith({genre:['Drama'],watch:'watched'});
    await fireEvent.click(within(watch).getByRole('button',{name:'All'}));
    expect(apply).toHaveBeenLastCalledWith({genre:['Drama']});
  });
  it('hides the watch pills without watch state', () => {
    render(CatalogFilterBar,{props:{facets,filters:{},onapply:vi.fn()}});
    expect(screen.queryByRole('group',{name:'Watch status'})).toBeNull();
  });
  it('removes one active filter while preserving the other groups', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{genre:['Drama','Comedy'],watch:'unwatched'},onapply:apply}});
    const active=screen.getByRole('group',{name:'Active filters'});
    await fireEvent.click(within(active).getByRole('button',{name:/^Genre: Drama/}));
    expect(apply).toHaveBeenCalledWith({genre:['Comedy'],watch:'unwatched'});
    await fireEvent.click(screen.getByRole('button',{name:'Clear filters'}));
    expect(apply).toHaveBeenLastCalledWith({});
  });
  it('keeps active filters removable while facets load', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets:null,loading:true,filters:{genre:['Drama']},onapply:apply}});
    expect(screen.getByRole('button',{name:'Genre'})).toBeDisabled();
    await fireEvent.click(within(screen.getByRole('group',{name:'Active filters'})).getByRole('button',{name:/^Genre: Drama/}));
    expect(apply).toHaveBeenCalledWith({});
  });
});
