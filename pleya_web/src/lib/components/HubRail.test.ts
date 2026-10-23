import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { createRawSnippet } from 'svelte';
import { fireEvent, render, screen } from '@testing-library/svelte';

import HubRail from './HubRail.svelte';
import type { Item } from '../api/types';

vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } }
}));

function items(count: number): Item[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `i${i}`,
    kind: 'movie' as const,
    title: `Title ${i}`,
    added_at: '2026-01-01T00:00:00Z'
  }));
}

/**
 * jsdom doet geen layout: scrollWidth en clientWidth zijn 0. Een rij die
 * breder is dan zijn venster zetten we daarom met de hand neer.
 */
function layOut(track: HTMLElement, scrollWidth: number, clientWidth: number): void {
  Object.defineProperty(track, 'scrollWidth', { configurable: true, value: scrollWidth });
  Object.defineProperty(track, 'clientWidth', { configurable: true, value: clientWidth });
}

describe('HubRail', () => {
  it('tekent kop en rij wanneer er inhoud is', () => {
    render(HubRail, { props: { title: 'Recently added', items: items(4) } });
    expect(screen.getByRole('heading', { name: 'Recently added' })).toBeInTheDocument();
    expect(screen.getByRole('list', { name: 'Recently added' })).toBeInTheDocument();
    expect(screen.getAllByRole('listitem')).toHaveLength(4);
  });

  it('verdwijnt volledig bij een lege lijst', () => {
    // continue_watching en next_up leveren vandaag lege lijsten omdat er geen
    // kijkstatus is. Een kop boven niets zou beloven dat daar ooit iets komt.
    const { container } = render(HubRail, {
      props: { title: 'Continue watching', items: [], href: '/x' }
    });
    expect(container.querySelector('.rail')).toBeNull();
    expect(screen.queryByText('Continue watching')).toBeNull();
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('zet "View all" als eigen, altijd zichtbare link naast de titel', () => {
    const { container } = render(HubRail, {
      props: { title: 'Films', items: items(2), href: '/libraries/x' }
    });
    const link = screen.getByRole('link', { name: 'View all' });
    expect(link).toHaveAttribute('href', '/libraries/x');
    // Twee elementen: de titel is geen link en de link bevat de titel niet.
    const heading = screen.getByRole('heading', { name: 'Films' });
    expect(heading.closest('a')).toBeNull();
    expect(link).not.toHaveTextContent('Films');
    // De link verwijst naar zijn rij, zodat vijf keer "View all" te onderscheiden is.
    expect(link).toHaveAccessibleDescription('Films');
    // Geen klasse die hem tot hover verbergt, zoals de vorige versie deed.
    expect(container.querySelector('.rail__more')).toBeNull();
  });

  it('neemt een eigen label voor de link over', () => {
    render(HubRail, {
      props: { title: 'Films', items: items(2), href: '/x', viewAllLabel: 'See everything' }
    });
    expect(screen.getByRole('link', { name: 'See everything' })).toBeInTheDocument();
  });

  it('tekent zonder href geen link', () => {
    render(HubRail, { props: { title: 'Films', items: items(2) } });
    expect(screen.queryByRole('link', { name: 'View all' })).toBeNull();
  });

  it('noemt de pijlen via t() en koppelt ze aan het spoor', () => {
    render(HubRail, { props: { title: 'Films', items: items(2) } });
    const list = screen.getByRole('list', { name: 'Films' });
    for (const name of ['Scroll left', 'Scroll right']) {
      const button = screen.getByRole('button', { name });
      expect(button).toHaveAttribute('aria-controls', list.id);
    }
  });

  it('schakelt de linkerpijl uit op scrollpositie 0 en weer in na schuiven', async () => {
    render(HubRail, { props: { title: 'Films', items: items(12) } });
    const track = screen.getByRole('list', { name: 'Films' });
    const left = screen.getByRole('button', { name: 'Scroll left' });
    const right = screen.getByRole('button', { name: 'Scroll right' });
    const fade = document.querySelector('.rail__fade')!;

    expect(left).toHaveAttribute('aria-disabled', 'true');

    // Negatieve kant: een rij van 2000 in een venster van 800 staat niet aan
    // het eind, dus rechts kan wel en de fade staat aan.
    layOut(track, 2000, 800);
    await fireEvent.scroll(track);
    await vi.waitFor(() => expect(right).toHaveAttribute('aria-disabled', 'false'));
    expect(fade).toHaveClass('rail__fade--on');
    expect(left).toHaveAttribute('aria-disabled', 'true');

    track.scrollLeft = 400;
    await fireEvent.scroll(track);
    await vi.waitFor(() => expect(left).toHaveAttribute('aria-disabled', 'false'));

    // Aan het eind: rechts uit en de fade weg, want er valt niets meer te schuiven.
    track.scrollLeft = 1200;
    await fireEvent.scroll(track);
    await vi.waitFor(() => expect(right).toHaveAttribute('aria-disabled', 'true'));
    expect(fade).not.toHaveClass('rail__fade--on');
  });

  it('meet opnieuw als de rij groeit, zonder dat er gescrold is', async () => {
    const view = render(HubRail, { props: { title: 'Films', items: items(2) } });
    const track = screen.getByRole('list', { name: 'Films' });
    const right = screen.getByRole('button', { name: 'Scroll right' });
    const fade = document.querySelector('.rail__fade')!;
    expect(right).toHaveAttribute('aria-disabled', 'true');
    expect(fade).not.toHaveClass('rail__fade--on');

    // Er komen kaarten bij en de rij wordt breder dan zijn venster; er volgt
    // geen scroll-event en het spoor zelf verandert niet van maat.
    layOut(track, 2000, 800);
    await view.rerender({ title: 'Films', items: items(12) });
    await vi.waitFor(() => expect(right).toHaveAttribute('aria-disabled', 'false'));
    expect(fade).toHaveClass('rail__fade--on');
  });

  it('schuift niet met een uitgeschakelde pijl', async () => {
    render(HubRail, { props: { title: 'Films', items: items(3) } });
    const track = screen.getByRole('list', { name: 'Films' });
    const scrollBy = vi.fn();
    track.scrollBy = scrollBy;
    await fireEvent.click(screen.getByRole('button', { name: 'Scroll left' }));
    expect(scrollBy).not.toHaveBeenCalled();

    layOut(track, 2000, 800);
    await fireEvent.scroll(track);
    const right = screen.getByRole('button', { name: 'Scroll right' });
    await vi.waitFor(() => expect(right).toHaveAttribute('aria-disabled', 'false'));
    await fireEvent.click(right);
    expect(scrollBy).toHaveBeenCalledWith(expect.objectContaining({ left: 640 }));
  });

  it('laat een snippet de standaardkaart vervangen, met item en index', () => {
    const card = createRawSnippet((item: () => Item, index: () => number) => ({
      render: () => `<span class="own">${index()}:${item().title}</span>`
    }));
    const { container } = render(HubRail, {
      props: { title: 'Films', items: items(3), card }
    });
    const own = [...container.querySelectorAll('.own')].map((el) => el.textContent);
    expect(own).toEqual(['0:Title 0', '1:Title 1', '2:Title 2']);
    expect(container.querySelector('.card')).toBeNull();
  });

  it('geeft het spoor alleen een tabstop als de kaarten niets focusbaars hebben', async () => {
    const plain = createRawSnippet((item: () => Item) => ({
      render: () => `<span class="own">${item().title}</span>`
    }));
    const bare = render(HubRail, { props: { title: 'Plain', items: items(3), card: plain } });
    const track = screen.getByRole('list', { name: 'Plain' });
    await vi.waitFor(() => expect(track).toHaveAttribute('tabindex', '0'));
    bare.unmount();

    // Negatieve kant: met kaartlinks loopt de tab door de kaarten.
    render(HubRail, { props: { title: 'Linked', items: items(3) } });
    expect(screen.getByRole('list', { name: 'Linked' })).not.toHaveAttribute('tabindex');
  });

  it('zet de pijlen op de helft van het beeld, onder spoor- en kaartpadding', () => {
    const source = readFileSync(resolve(import.meta.dirname, 'HubRail.svelte'), 'utf8');
    expect(source).toContain(
      'top: calc(6px + var(--space-quarter) + var(--rail-art-h) / 2 - var(--touch-target) / 2)'
    );
  });

  it('tekent zonder snippet de standaardkaart', () => {
    const { container } = render(HubRail, { props: { title: 'Films', items: items(3) } });
    expect(container.querySelectorAll('.card')).toHaveLength(3);
  });

  it('geeft een rij die alleen afleveringen bevat de brede vorm', () => {
    const { container } = render(HubRail, {
      props: {
        title: 'Episodes',
        items: [
          { id: 'a', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' },
          { id: 'b', kind: 'episode', title: 'E2', added_at: '2026-01-01T00:00:00Z' }
        ] as Item[]
      }
    });
    expect(container.querySelector('.rail--wide')).not.toBeNull();
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(2);
    expect(container.querySelectorAll('.artwork--poster')).toHaveLength(0);
  });

  it('laat een opgegeven vorm de afleiding overschrijven en geeft hem aan de snippet', () => {
    // Afleveringen als serieposter: zonder override kreeg de posterkaart een
    // cel van 1,78 keer de posterbreedte.
    const card = createRawSnippet(
      (item: () => Item, _index: () => number, shape: () => 'poster' | 'wide') => ({
        render: () => `<span class="own" data-shape="${shape()}">${item().title}</span>`
      })
    );
    const { container } = render(HubRail, {
      props: {
        title: 'Continue watching',
        shape: 'poster',
        card,
        items: [
          { id: 'a', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' },
          { id: 'b', kind: 'episode', title: 'E2', added_at: '2026-01-01T00:00:00Z' }
        ] as Item[]
      }
    });
    expect(container.querySelector('.rail--wide')).toBeNull();
    const shapes = [...container.querySelectorAll('.own')].map((el) => el.getAttribute('data-shape'));
    expect(shapes).toEqual(['poster', 'poster']);
  });

  it('geeft de afgeleide vorm aan de snippet als er geen override is', () => {
    const card = createRawSnippet(
      (_item: () => Item, _index: () => number, shape: () => 'poster' | 'wide') => ({
        render: () => `<span class="own" data-shape="${shape()}"></span>`
      })
    );
    const { container } = render(HubRail, {
      props: {
        title: 'Episodes',
        card,
        items: [{ id: 'a', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' }] as Item[]
      }
    });
    expect(container.querySelector('.rail--wide')).not.toBeNull();
    expect(container.querySelector('.own')).toHaveAttribute('data-shape', 'wide');
  });

  it('houdt een gemengde rij op één hoogte, met de poster als vorm', () => {
    const { container } = render(HubRail, {
      props: {
        title: 'Recently added',
        items: [
          { id: 'a', kind: 'episode', title: 'E', added_at: '2026-01-01T00:00:00Z' },
          { id: 'b', kind: 'movie', title: 'M', added_at: '2026-01-01T00:00:00Z' }
        ] as Item[]
      }
    });
    expect(container.querySelector('.rail--wide')).toBeNull();
    expect(container.querySelectorAll('.artwork--poster')).toHaveLength(2);
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(0);
  });

  it('deelt zijn geometrie met de skeletrail, uit dezelfde tokens', () => {
    // jsdom past geen componentstijl toe, dus dit contract leest de bron: rail
    // en skelet moeten dezelfde inzet, ruimte en celbreedte gebruiken, anders
    // verspringt Home zodra de rij binnenkomt.
    for (const file of ['HubRail.svelte', 'SkeletonPage.svelte']) {
      const source = readFileSync(resolve(import.meta.dirname, file), 'utf8');
      expect(source, file).toContain('gap: var(--rail-gap)');
      expect(source, file).toContain('padding: 6px var(--inset) 4px');
      expect(source, file).toMatch(/flex: 0 0 var\(--(poster-w|rail-cell)\)/);
      expect(source, file).not.toContain('--rail-cell-w');
    }
    const tokens = readFileSync(resolve(import.meta.dirname, '../../styles/tokens.css'), 'utf8');
    expect(tokens).not.toContain('--rail-cell-w');
  });

  it('zet een pijl met toetsenbordfocus op volle dekking, ook als hij uit staat', () => {
    // jsdom past geen componentstijl toe; de regel moet na de dimregel staan
    // en minstens even specifiek zijn, anders blijft de ring op 0,35.
    const source = readFileSync(resolve(import.meta.dirname, 'HubRail.svelte'), 'utf8');
    const dim = source.indexOf(".rail:focus-within .rail__arrow[aria-disabled='true'] {");
    const focus = source.indexOf('.rail:focus-within .rail__arrow:focus-visible {');
    expect(dim).toBeGreaterThan(-1);
    expect(focus).toBeGreaterThan(dim);
    expect(source.slice(focus, source.indexOf('}', focus))).toContain('opacity: 1;');
  });
});
