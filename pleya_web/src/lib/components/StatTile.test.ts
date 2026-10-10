import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import StatTile from './StatTile.svelte';

describe('StatTile', () => {
  it('koppelt label en waarde als term en definitie', () => {
    render(StatTile, { props: { label: 'Storage', value: '3.2 TB free', sub: 'of 16 TB' } });
    expect(screen.getByRole('term')).toHaveTextContent('Storage');
    const defs = screen.getAllByRole('definition');
    expect(defs.map((d) => d.textContent)).toEqual(['3.2 TB free', 'of 16 TB']);
    expect(defs[0]).toHaveClass('stat__value');
  });

  it('laat de toelichting weg als die er niet is', () => {
    render(StatTile, { props: { label: 'Libraries', value: '4' } });
    expect(screen.getAllByRole('definition')).toHaveLength(1);
  });

  it('houdt het icoon buiten de toegankelijkheidsboom', () => {
    const icon = createRawSnippet(() => ({ render: () => '<svg data-testid="ic"></svg>' }));
    render(StatTile, { props: { label: 'Scan', value: 'running', icon } });
    expect(screen.getByTestId('ic').parentElement).toHaveAttribute('aria-hidden', 'true');
  });
});
