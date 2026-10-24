import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { createRawSnippet } from 'svelte';

import Choice, { type ChoiceOption } from './Choice.svelte';

const options: ChoiceOption[] = [
  { value: 'movies', label: 'Movies', description: 'One film per folder' },
  { value: 'shows', label: 'Shows' },
  { value: 'books', label: 'Books', disabled: true }
];

describe('Choice', () => {
  it('is een groep met de legenda als naam en radio’s met omschrijving', () => {
    render(Choice, { props: { legend: 'Kind', options, value: 'movies' } });
    expect(screen.getByRole('radiogroup', { name: 'Kind' })).toBeInTheDocument();
    const movies = screen.getByRole('radio', { name: 'Movies' });
    expect(movies).toBeChecked();
    expect(movies).toHaveAccessibleDescription('One film per folder');
  });

  it('kiest met een klik op de kaart en meldt de keuze', async () => {
    const seen: string[] = [];
    render(Choice, {
      props: { legend: 'Kind', options, value: 'movies', onchange: (v: string) => seen.push(v) }
    });
    await userEvent.click(screen.getByText('Shows'));
    expect(screen.getByRole('radio', { name: 'Shows' })).toBeChecked();
    expect(screen.getByRole('radio', { name: 'Movies' })).not.toBeChecked();
    expect(seen).toEqual(['shows']);
  });

  it('heeft één tabstop en loopt met de pijltjes langs de opties', async () => {
    render(Choice, { props: { legend: 'Kind', options, value: 'movies' } });
    await userEvent.tab();
    expect(screen.getByRole('radio', { name: 'Movies' })).toHaveFocus();

    await userEvent.keyboard('{ArrowDown}');
    const shows = screen.getByRole('radio', { name: 'Shows' });
    expect(shows).toHaveFocus();
    expect(shows).toBeChecked();
  });

  it('laat een uitgeschakelde optie of groep niet kiezen', async () => {
    const { unmount } = render(Choice, { props: { legend: 'Kind', options, value: 'movies' } });
    const books = screen.getByRole('radio', { name: 'Books' });
    expect(books).toBeDisabled();
    await userEvent.click(screen.getByText('Books'));
    expect(books).not.toBeChecked();
    unmount();

    render(Choice, { props: { legend: 'Kind', options, value: 'movies', disabled: true } });
    for (const radio of screen.getAllByRole('radio')) expect(radio).toBeDisabled();
  });

  it('beschrijft de groep met de fout en markeert hem ongeldig', () => {
    render(Choice, { props: { legend: 'Kind', options, error: 'Pick a kind', hint: 'Fixed later' } });
    const group = screen.getByRole('radiogroup', { name: 'Kind' });
    expect(group).toHaveAttribute('aria-invalid', 'true');
    expect(group).toHaveAccessibleDescription('Pick a kind Fixed later');
  });

  it('geeft de tegelvorm drie kolommen, of het gevraagde aantal', () => {
    const { unmount } = render(Choice, { props: { legend: 'Kind', options, layout: 'grid' } });
    expect(screen.getByRole('radiogroup').style.getPropertyValue('--cho-cols')).toBe('3');
    unmount();

    render(Choice, { props: { legend: 'Kind', options, layout: 'grid', columns: 2 } });
    expect(screen.getByRole('radiogroup').style.getPropertyValue('--cho-cols')).toBe('2');
  });

  it('tekent in de tegelvorm een icoon per optie, verborgen voor een schermlezer', () => {
    const icon = createRawSnippet((o: () => ChoiceOption) => ({
      render: () => `<svg data-testid="icon-${o().value}"></svg>`
    }));
    render(Choice, { props: { legend: 'Kind', options, layout: 'grid', icon } });
    const svg = screen.getByTestId('icon-movies');
    expect(svg.parentElement).toHaveAttribute('aria-hidden', 'true');
  });
});
