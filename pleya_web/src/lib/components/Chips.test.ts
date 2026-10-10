import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import Chips from './Chips.svelte';

const options = [
  { id: 'all', label: 'All' },
  { id: 'movies', label: 'Movies', count: 3 },
  { id: 'shows', label: 'Shows' }
];

describe('Chips', () => {
  it('is een benoemde groep toggle-buttons met aria-pressed', () => {
    render(Chips, { props: { label: 'Filter', options, selected: ['all'] } });
    expect(screen.getByRole('group', { name: 'Filter' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: 'Movies 3' })).toHaveAttribute(
      'aria-pressed',
      'false'
    );
  });

  it('houdt zonder multiple precies één chip ingedrukt', async () => {
    const seen: string[][] = [];
    render(Chips, {
      props: { label: 'Filter', options, selected: ['all'], onchange: (s: string[]) => seen.push(s) }
    });
    const all = screen.getByRole('button', { name: 'All' });
    const shows = screen.getByRole('button', { name: 'Shows' });

    await userEvent.click(shows);
    expect(shows).toHaveAttribute('aria-pressed', 'true');
    expect(all).toHaveAttribute('aria-pressed', 'false');

    // Nog eens op de gekozen chip drukken laat hem staan en meldt niets.
    await userEvent.click(shows);
    expect(shows).toHaveAttribute('aria-pressed', 'true');
    expect(seen).toEqual([['shows']]);
  });

  it('schakelt met multiple elke chip los, ook met spatie en Enter', async () => {
    const seen: string[][] = [];
    render(Chips, {
      props: { label: 'Filter', options, multiple: true, onchange: (s: string[]) => seen.push(s) }
    });

    await userEvent.tab();
    const all = screen.getByRole('button', { name: 'All' });
    expect(all).toHaveFocus();
    await userEvent.keyboard(' ');
    expect(all).toHaveAttribute('aria-pressed', 'true');

    await userEvent.tab();
    const movies = screen.getByRole('button', { name: 'Movies 3' });
    expect(movies).toHaveFocus();
    await userEvent.keyboard('{Enter}');
    expect(movies).toHaveAttribute('aria-pressed', 'true');

    await userEvent.keyboard('{Enter}');
    expect(movies).toHaveAttribute('aria-pressed', 'false');
    expect(seen).toEqual([['all'], ['all', 'movies'], ['all']]);
  });

  it('tekent de gekozen variant', () => {
    render(Chips, { props: { label: 'Filter', options, variant: 'quiet', selected: ['all'] } });
    expect(screen.getByText('All')).toHaveClass('chip--quiet', 'chip--on');
    expect(screen.getByText('Shows')).not.toHaveClass('chip--on');
  });
});
