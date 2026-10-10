import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { createRawSnippet } from 'svelte';

import Field, { type FieldControl } from './Field.svelte';

describe('Field', () => {
  it('hangt het label aan de invoer en de hint via aria-describedby', () => {
    render(Field, { props: { label: 'Name', hint: 'Shown in the apps' } });
    const input = screen.getByRole('textbox', { name: 'Name' });
    expect(input).toHaveAccessibleDescription('Shown in the apps');
    expect(input).not.toHaveAttribute('aria-invalid');
  });

  it('zet bij een fout aria-invalid en noemt de fout vóór de hint', () => {
    render(Field, { props: { label: 'Name', hint: 'Shown in the apps', error: 'Required' } });
    const input = screen.getByRole('textbox', { name: 'Name' });
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(input).toHaveAccessibleDescription('Required Shown in the apps');
  });

  it('neemt toetsenbordinvoer aan en meldt de waarde', async () => {
    const seen: string[] = [];
    render(Field, { props: { label: 'Name', oninput: (v: string) => seen.push(v) } });
    const input = screen.getByRole('textbox', { name: 'Name' });

    await userEvent.type(input, 'Films');
    expect(input).toHaveValue('Films');
    expect(seen.at(-1)).toBe('Films');
  });

  it('is uitgeschakeld te tekenen en neemt dan niets aan', async () => {
    render(Field, { props: { label: 'Name', disabled: true } });
    const input = screen.getByRole('textbox', { name: 'Name' });
    expect(input).toBeDisabled();

    await userEvent.type(input, 'x');
    expect(input).toHaveValue('');
  });

  it('geeft een eigen besturingselement dezelfde bedrading mee', () => {
    const control = createRawSnippet((c: () => FieldControl) => ({
      render: () =>
        `<input id="${c().id}" aria-describedby="${c().describedby}" aria-invalid="${c().invalid}" />`
    }));
    render(Field, { props: { label: 'Type DELETE', error: 'Does not match', children: control } });

    const input = screen.getByRole('textbox', { name: 'Type DELETE' });
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(input).toHaveAccessibleDescription('Does not match');
  });

  it('houdt het label voor een schermlezer als het visueel weg moet', () => {
    render(Field, { props: { label: 'Search', hideLabel: true } });
    expect(screen.getByText('Search')).toHaveClass('visually-hidden');
    expect(screen.getByRole('textbox', { name: 'Search' })).toBeInTheDocument();
  });
});
