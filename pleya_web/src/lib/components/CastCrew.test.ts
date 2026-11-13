import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import CastCrew from './CastCrew.svelte';

describe('cast en crew', () => {
  it('toont naam, rol en initialen, zonder foto of link', () => {
    render(CastCrew, { props: { people: [
      { name: 'Zendaya', role: 'actor', character: 'Chani' },
      { name: 'Denis Villeneuve', role: 'director' },
      { name: 'Rebecca Ferguson', role: 'actor' }
    ] } });
    expect(screen.getByRole('heading', { name: 'Cast and crew' })).toBeInTheDocument();
    const people = screen.getAllByRole('listitem').map(entry => entry.textContent?.replace(/\s+/g, ' ').trim());
    // Regie eerst; een acteur zonder personage krijgt de rolnaam.
    expect(people).toEqual(['DV Denis VilleneuveDirector', 'Z ZendayaChani', 'RF Rebecca FergusonActor']);
    expect(document.querySelector('img, a')).toBeNull();
  });

  it.each([[undefined], [null], [[]], [[{ name: '  ', role: 'actor' as const }]]])('toont geen sectie zonder personen (%j)', people => {
    render(CastCrew, { props: { people } });
    expect(screen.queryByRole('heading')).toBeNull();
    expect(screen.queryByRole('list')).toBeNull();
  });
});
