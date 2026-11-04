import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import CatalogFilterBar from './CatalogFilterBar.svelte';
import type { Facets } from '../api/types';

const facets: Facets = {
  genres: [{value:'Drama',count:2},{value:'Comedy',count:1}],
  years: [{value:'2025',count:2}], content_ratings: [], audio_languages: [],
  resolutions: [{value:'fhd',count:2},{value:'future',count:1}],
  watch: {unwatched:2,in_progress:1,watched:1}
};

describe('catalog filter controls', () => {
  it('edits a draft and applies it only after confirmation', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{},onapply:apply}});
    await fireEvent.click(screen.getByRole('button',{name:'Filters'}));
    const dialog=await screen.findByRole('dialog',{name:'Filters'});
    await fireEvent.click(within(dialog).getByRole('button',{name:/^Drama/}));
    expect(apply).not.toHaveBeenCalled();
    expect(within(dialog).getByRole('button',{name:/future/})).toBeDisabled();
    await fireEvent.click(within(dialog).getByRole('button',{name:'Apply filters'}));
    expect(apply).toHaveBeenCalledWith(expect.objectContaining({genre:['Drama']}));
    await waitFor(()=>expect(screen.queryByRole('dialog')).toBeNull());
  });
  it('cancels a draft and restores focus without changing filters', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{},onapply:apply}});
    const opener=screen.getByRole('button',{name:'Filters'});
    opener.focus(); await fireEvent.click(opener);
    const dialog=await screen.findByRole('dialog');
    await fireEvent.click(within(dialog).getByRole('button',{name:/^Drama/}));
    await fireEvent.keyDown(document,{key:'Escape'});
    await waitFor(()=>expect(screen.queryByRole('dialog')).toBeNull());
    expect(apply).not.toHaveBeenCalled(); expect(opener).toHaveFocus();
    await fireEvent.click(opener);
    expect(within(await screen.findByRole('dialog')).getByRole('button',{name:/^Drama/})).toHaveAttribute('aria-pressed','false');
  });
  it('removes one active filter while preserving the other groups', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets,filters:{genre:['Drama','Comedy'],watch:'unwatched'},onapply:apply}});
    const active=screen.getByRole('group',{name:'Active filters'});
    await fireEvent.click(within(active).getByRole('button',{name:'Drama'}));
    expect(apply).toHaveBeenCalledWith({genre:['Comedy'],watch:'unwatched'});
  });
  it('keeps active filters removable while facets load', async () => {
    const apply=vi.fn();
    render(CatalogFilterBar,{props:{facets:null,loading:true,filters:{genre:['Drama']},onapply:apply}});
    expect(screen.getByRole('button',{name:/^Filters/})).toBeDisabled();
    await fireEvent.click(within(screen.getByRole('group',{name:'Active filters'})).getByRole('button',{name:'Drama'}));
    expect(apply).toHaveBeenCalledWith({});
  });
});
