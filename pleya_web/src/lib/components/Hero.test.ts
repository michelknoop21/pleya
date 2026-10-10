import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import Hero from './Hero.svelte';
import { ARTWORK_LOADER_KEY } from './artworkLoader';
import type { Item } from '../api/types';

vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } }
}));

function movie(patch: Partial<Item> = {}): Item {
  return {
    id: 'm1',
    kind: 'movie',
    title: 'Blade Runner',
    added_at: '2026-01-01T00:00:00Z',
    year: 1982,
    duration_ms: 6_960_000,
    ...patch
  } as Item;
}

/** De zichtbare delen van de metaregel, zonder de punten ertussen. */
function metaParts(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll('.hero__meta > span:not([aria-hidden])')).map(
    (el) => el.textContent ?? ''
  );
}

describe('Hero', () => {
  it('toont de titel als de kop van de pagina, in de displayletter', () => {
    render(Hero, { props: { item: movie() } });
    const heading = screen.getByRole('heading', { level: 1, name: 'Blade Runner' });
    expect(heading).toHaveClass('t-display-face');
  });

  it('zet soort, jaar en duur op één regel, met punten die een schermlezer overslaat', () => {
    const { container } = render(Hero, { props: { item: movie() } });
    expect(metaParts(container)).toEqual(['Movie', '1982', '1h 56m']);
    const dots = container.querySelectorAll('.hero__meta > [aria-hidden="true"]');
    expect(dots).toHaveLength(2);
  });

  it('laat ontbrekende metadata weg in plaats van een lege plek te tonen', () => {
    const { container } = render(Hero, {
      props: { item: movie({ year: undefined, duration_ms: undefined }) }
    });
    expect(metaParts(container)).toEqual(['Movie']);
    expect(container.querySelectorAll('.hero__meta > [aria-hidden="true"]')).toHaveLength(0);
  });

  it('heeft zonder playHref geen afspeelknop, alleen Meer info naar het item', () => {
    const { container } = render(Hero, { props: { item: movie() } });
    // Ook geen <a> zonder href: die heeft geen linkrol en zou hieronder ontsnappen.
    expect(container.querySelectorAll('.hero__cta a')).toHaveLength(1);
    expect(screen.queryByText('Play')).toBeNull();
    const links = screen.getAllByRole('link');
    expect(links).toHaveLength(1);
    expect(screen.getByRole('link', { name: 'More info' })).toHaveAttribute('href', '/items/m1');
    expect(screen.queryByRole('link', { name: 'Play' })).toBeNull();
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('toont Afspelen vóór Meer info wanneer de aanroeper een bestemming meegeeft', () => {
    render(Hero, { props: { item: movie(), playHref: '/play/m1' } });
    const links = screen.getAllByRole('link');
    expect(links.map((l) => l.textContent?.trim())).toEqual(['Play', 'More info']);
    expect(screen.getByRole('link', { name: 'Play' })).toHaveAttribute('href', '/play/m1');
    // Meer info blijft naar het item wijzen, niet naar de speler.
    expect(screen.getByRole('link', { name: 'More info' })).toHaveAttribute('href', '/items/m1');
  });

  it('toont een synopsis alleen als die meegegeven is', () => {
    const { container, unmount } = render(Hero, { props: { item: movie() } });
    expect(container.querySelector('.hero__summary')).toBeNull();
    unmount();
    render(Hero, { props: { item: movie(), summary: 'Een replicant op de vlucht.' } });
    expect(screen.getByText('Een replicant op de vlucht.')).toHaveClass('hero__summary');
  });

  it('noemt de sectie met de standaardnaam, of met een eigen label', () => {
    const { unmount } = render(Hero, { props: { item: movie() } });
    expect(screen.getByRole('region', { name: 'Recently added' })).toBeInTheDocument();
    unmount();
    render(Hero, { props: { item: movie(), label: 'Uitgelicht' } });
    expect(screen.getByRole('region', { name: 'Uitgelicht' })).toBeInTheDocument();
  });

  it('vraagt de backdrop op en niet de poster, als backdrop', async () => {
    const loader = vi.fn().mockResolvedValue(new Blob(['x']));
    const { container } = render(Hero, {
      props: { item: movie({ artwork: { poster_id: 'p1', backdrop_id: 'b1' } }) },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    await vi.waitFor(() => expect(loader).toHaveBeenCalled());
    expect(loader.mock.calls[0]?.[0]).toBe('b1');
    expect(container.querySelector('.artwork--flat')).not.toBeNull();
    expect(container.querySelector('.hero__scrim')).not.toBeNull();
    expect(container.querySelector('.hero')).not.toHaveClass('hero--none');
  });

  it('valt terug op de poster als er geen backdrop is', async () => {
    const loader = vi.fn().mockResolvedValue(new Blob(['x']));
    render(Hero, {
      props: { item: movie({ artwork: { poster_id: 'p1' } }) },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    await vi.waitFor(() => expect(loader).toHaveBeenCalled());
    expect(loader.mock.calls[0]?.[0]).toBe('p1');
  });

  it('tekent zonder artwork het paneel, zonder beeldvlak en zonder waas', () => {
    const { container } = render(Hero, { props: { item: movie() } });
    expect(container.querySelector('.hero')).toHaveClass('hero--none');
    expect(container.querySelector('.artwork')).toBeNull();
    expect(container.querySelector('.hero__scrim')).toBeNull();
    // De tekst en Meer info staan er gewoon.
    expect(screen.getByRole('link', { name: 'More info' })).toBeInTheDocument();
  });

  it('laat waas en tekstinkt de themawaarden volgen', () => {
    // jsdom rekent geen color-mix uit; het contrast zelf staat in het
    // fixrapport (pixelmeting in licht, donker en OLED). Dit contract houdt
    // vast dat de dekkingen uit de thematokens komen en niet vast staan.
    const source = readFileSync(resolve(import.meta.dirname, 'Hero.svelte'), 'utf8');
    const style = source.slice(source.indexOf('<style>'));
    expect(style).toContain('calc(var(--scrim-strong) * 102%)');
    expect(style).toContain('calc(var(--scrim-mid) * 89%)');
    expect(style).toContain('min(100%, var(--scrim-strong) * 104%)');
    expect(style).not.toMatch(/var\(--scrim\) \d+%/);
    expect(style).toContain('var(--on-artwork) calc(var(--on-artwork-ink) * 100%)');
    expect(style.match(/color: var\(--hero-ink\)/g)).toHaveLength(2);
  });

  it('schaalt de titel onder 900 mee en compenseert de spatiëring', () => {
    const source = readFileSync(resolve(import.meta.dirname, 'Hero.svelte'), 'utf8');
    const narrow = source.slice(source.indexOf('@media (max-width: 899px)'));
    expect(narrow).toContain('font-size: clamp(22px, 7vw, 32px)');
    expect(narrow).toContain('padding-inline-start: 0.2em');
    // De vangrail tegen overlopen blijft op de basisregel staan.
    expect(source).toContain('overflow-wrap: break-word');
  });

  it('zet de artworkinkt in light op 0,9', () => {
    // Met 0,8 haalde de synopsis op 16:9 rond 900 over donker artwork 3,93:1
    // (pixelmeting in het fixrapport); 0,9 brengt hem op 4,52.
    const tokens = readFileSync(resolve(import.meta.dirname, '../../styles/tokens.css'), 'utf8');
    const light = tokens.slice(tokens.indexOf("[data-theme='light']"));
    expect(light.slice(0, light.indexOf('}'))).toMatch(/--on-artwork-ink: 0\.9;/);
  });

  it('laat app.html de displayletter van de titel vooraf laden, na de CSP-meta', () => {
    const html = readFileSync(resolve(import.meta.dirname, '../../app.html'), 'utf8');
    const link = html.match(/<link\s+rel="preload"[^>]*ArchivoBlack-Regular\.woff2"[^>]*>/);
    expect(link, 'preload voor ArchivoBlack').not.toBeNull();
    expect(link![0]).toContain('as="font"');
    expect(link![0]).toContain('crossorigin');
    expect(html.indexOf('%sveltekit.head%')).toBeLessThan(html.indexOf(link![0]));
  });
});
