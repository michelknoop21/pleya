import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ search: vi.fn(), libraries: [{ id: 'l', kind: 'movies' }] as { id: string; kind: string }[], url: new URL('http://x/search') }));
vi.mock('$app/state', () => ({ page: { get url() { return h.url; }, state: {} } }));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('../../lib/stores/session.svelte.js', () => ({ session: { client: { search: h.search }, get libraries() { return h.libraries; } } }));
import Search from './+page.svelte';
const item = (id: string, kind: string) => ({ id, title: id, kind, added_at: '2026-10-30T00:00:00Z' });
const page = (items: unknown[], next_cursor: string | null = null) => ({ items, next_cursor });
const type = (value: string) => fireEvent.input(screen.getByRole('searchbox'), { target: { value } });
beforeEach(() => {
  h.url = new URL('http://x/search');
  h.libraries = [{ id: 'l', kind: 'movies' }];
  h.search.mockReset().mockResolvedValue(page([]));
});
afterEach(() => vi.useRealTimers());
describe('search route', () => {
  it('groups results per kind with a count', async () => {
    h.search.mockResolvedValueOnce(page([item('Dune', 'movie'), item('Dune 2', 'movie'), item('Fallout', 'episode')]));
    render(Search);
    await type('dune');
    expect(await screen.findByRole('heading', { name: 'Movies 2' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Episodes 1' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: /Shows/ })).toBeNull();
  });
  it('walks the cursor of the term that produced the results', async () => {
    h.search.mockResolvedValueOnce(page([item('One', 'movie')], 'next')).mockResolvedValueOnce(page([item('Two', 'show')]));
    render(Search);
    await type('o');
    expect(await screen.findByRole('heading', { name: 'Movies 1+' })).toBeInTheDocument();
    await fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByRole('heading', { name: 'Shows 1' });
    expect(h.search).toHaveBeenLastCalledWith({ q: 'o', limit: 100, cursor: 'next' }, expect.any(AbortSignal));
  });
  it('offers a way out of an empty result: the last term with hits and the catalog', async () => {
    h.search.mockResolvedValueOnce(page([item('Dune', 'movie')])).mockResolvedValueOnce(page([]));
    render(Search);
    await type('dune');
    await screen.findByRole('heading', { name: 'Movies 1' });
    await type('dunne');
    const back = await screen.findByRole('button', { name: 'Did you mean “dune”?' });
    expect(screen.getByRole('heading', { name: 'Nothing found for “dunne”' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Browse all films' })).toHaveAttribute('href', '/films');
    h.search.mockResolvedValueOnce(page([item('Dune', 'movie')]));
    await fireEvent.click(back);
    await waitFor(() => expect(screen.getByRole('searchbox')).toHaveValue('dune'));
    await screen.findByRole('heading', { name: 'Movies 1' });
  });
  it('points at the libraries without a film library and has no suggestion on a first miss', async () => {
    h.libraries = [{ id: 's', kind: 'shows' }];
    render(Search);
    await type('x');
    expect(await screen.findByRole('link', { name: 'Browse libraries' })).toHaveAttribute('href', '/libraries');
    expect(screen.queryByRole('button', { name: /Did you mean/ })).toBeNull();
  });
  it('clears the term and returns focus to the field', async () => {
    render(Search);
    await type('x');
    await fireEvent.click(screen.getByRole('button', { name: 'Clear search' }));
    expect(screen.getByRole('searchbox')).toHaveValue('');
    expect(screen.getByRole('searchbox')).toHaveFocus();
  });
  it('shows a failure with a retry', async () => {
    h.search.mockRejectedValueOnce(new Error('offline'));
    render(Search);
    await type('x');
    await fireEvent.click(await screen.findByRole('button', { name: 'Retry' }));
    await screen.findByRole('heading', { name: 'Nothing found for “x”' });
  });
  it('never lets an older answer overwrite a newer term', async () => {
    let answerOld: (value: unknown) => void = () => undefined;
    h.search.mockImplementationOnce(() => new Promise((resolve) => (answerOld = resolve))).mockResolvedValueOnce(page([item('New', 'movie')]));
    render(Search);
    await type('old');
    await waitFor(() => expect(h.search).toHaveBeenCalledTimes(1));
    await type('new');
    await screen.findByRole('heading', { name: 'Movies 1' });
    answerOld(page([item('Stale', 'movie'), item('Stale 2', 'movie')]));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByText('Stale')).toBeNull();
  });
});
