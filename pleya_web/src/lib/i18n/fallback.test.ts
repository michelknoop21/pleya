import { afterEach, describe, expect, it, vi } from 'vitest';

// De echte Nederlandse catalogus is volledig (`satisfies` in web.nl.ts), dus
// daarmee is de terugval per sleutel niet te raken. Hier is hij leeg, zodat elke
// Nederlandse opzoeking misgaat en alleen de Engelse terugval het antwoord kan
// leveren. In een eigen bestand, omdat `vi.mock` voor het hele bestand geldt.
vi.mock('./web.nl', () => ({ webNl: {} }));
vi.mock('./shared', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./shared')>()),
  sharedNl: {}
}));

const { plural, setLocale, t } = await import('./index');

afterEach(() => setLocale('en'));

describe('terugval per sleutel', () => {
  it('geeft de Engelse tekst als de Nederlandse catalogus de sleutel niet heeft', () => {
    setLocale('nl');
    expect(t('rail.viewAll')).toBe('View all');
    expect(t('hero.play')).toBe('Play');
    expect(plural('item.seasonsCount', 3)).toBe('3 seasons');
  });

  it('geeft de sleutel zelf als geen enkele catalogus hem kent', () => {
    setLocale('nl');
    expect(t('bestaat.niet' as never)).toBe('bestaat.niet');
  });
});
