import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  LOCALES,
  LOCALE_STORAGE_KEY,
  changeLocale,
  initLocale,
  intlLocale,
  locale,
  pickLocale,
  plural,
  resolveLocale,
  setLocale,
  t
} from './index';

/**
 * Eigen opslag per test. Node 26 zet een eigen `localStorage` op de globale
 * scope die zonder `--localstorage-file` leeg (`undefined`) blijft en die van
 * jsdom overschaduwt; zonder deze stub hangt de test af van de Node-versie.
 */
function memoryStorage(): Storage {
  const data = new Map<string, string>();
  return {
    get length() {
      return data.size;
    },
    key: (index: number) => [...data.keys()][index] ?? null,
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, String(value)),
    removeItem: (key: string) => void data.delete(key),
    clear: () => data.clear()
  };
}

beforeEach(() => {
  vi.stubGlobal('localStorage', memoryStorage());
});

// De actieve taal is moduletoestand; elke test begint weer in het Engels,
// anders hangt de uitkomst van de volgorde af.
afterEach(() => {
  vi.unstubAllGlobals();
  setLocale('en');
  document.documentElement.lang = 'en';
});

describe('taalkeuze', () => {
  it('kiest de catalogus die bij de browsertaal past', () => {
    expect(pickLocale(['en-GB', 'nl'])).toBe('en');
    expect(pickLocale(['nl-NL'])).toBe('nl');
  });

  it('valt terug op Engels bij een taal die er niet is', () => {
    expect(pickLocale(['ja'])).toBe('en');
    expect(pickLocale([])).toBe('en');
  });

  it('kent Engels en Nederlands', () => {
    expect([...LOCALES]).toEqual(['en', 'nl']);
  });
});

describe('resolveLocale', () => {
  it('volgt de browsertaal als er niets bewaard is', () => {
    expect(resolveLocale(null, ['nl-NL'])).toBe('nl');
    expect(resolveLocale(null, ['en-GB', 'nl'])).toBe('en');
  });

  it('laat een bewaarde keuze winnen van de browser', () => {
    expect(resolveLocale('nl', ['en-US'])).toBe('nl');
  });

  it('negeert een onbekende bewaarde waarde', () => {
    expect(resolveLocale('fr', ['nl-BE'])).toBe('nl');
  });

  it('valt terug op Engels', () => {
    expect(resolveLocale(null, ['ja'])).toBe('en');
    expect(resolveLocale(null, [])).toBe('en');
  });
});

describe('initLocale', () => {
  it('zet html-lang op de bewaarde taal', () => {
    localStorage.setItem(LOCALE_STORAGE_KEY, 'nl');
    vi.spyOn(navigator, 'languages', 'get').mockReturnValue(['en-US']);
    expect(initLocale()).toBe('nl');
    expect(document.documentElement.lang).toBe('nl');
    expect(locale()).toBe('nl');
    expect(intlLocale()).toBe('nl-NL');
  });

  it('valt bij geweigerde opslag terug op de browser, en daarna op Engels', () => {
    document.documentElement.lang = 'nl';
    vi.spyOn(localStorage, 'getItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError');
    });
    vi.spyOn(navigator, 'languages', 'get').mockReturnValue(['ja']);
    expect(initLocale()).toBe('en');
    expect(document.documentElement.lang).toBe('en');
  });

  it('geeft bij een tweede aanroep hetzelfde', () => {
    localStorage.setItem(LOCALE_STORAGE_KEY, 'nl');
    expect(initLocale()).toBe(initLocale());
  });
});

describe('changeLocale', () => {
  it('bewaart de keuze en herlaadt één keer', () => {
    const reload = vi.fn();
    changeLocale('nl', reload);
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe('nl');
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('doet niets als de taal al actief is', () => {
    const reload = vi.fn();
    changeLocale('en', reload);
    expect(reload).not.toHaveBeenCalled();
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBeNull();
  });

  it('herlaadt niet als de opslag weigert, want dan gaat de keuze verloren', () => {
    vi.spyOn(localStorage, 'setItem').mockImplementation(() => {
      throw new DOMException('denied', 'QuotaExceededError');
    });
    const reload = vi.fn();
    changeLocale('nl', reload);
    expect(reload).not.toHaveBeenCalled();
    expect(locale()).toBe('nl');
  });
});

describe('intlLocale', () => {
  it('geeft Engels kaal en Nederlands met regio', () => {
    expect(intlLocale()).toBe('en');
    setLocale('nl');
    expect(intlLocale()).toBe('nl-NL');
  });
});

describe('vertalen', () => {
  it('haalt gedeelde teksten uit de i18n-bron van de app', () => {
    expect(t('states.emptyTitle')).toBe('Nothing here yet');
    expect(t('common.retry')).toBe('Retry');
  });

  it('vult plaatshouders in', () => {
    expect(t('item.season', { index: 3 })).toBe('Season 3');
  });

  it('laat een plaatshouder staan waar geen waarde voor is', () => {
    expect(t('item.season')).toContain('{index}');
  });
});

describe('meervoud', () => {
  it('kiest de vorm met Intl.PluralRules en niet met count === 1', () => {
    expect(plural('item.seasonsCount', 1)).toBe('1 season');
    expect(plural('item.seasonsCount', 0)).toBe('0 seasons');
    expect(plural('item.seasonsCount', 7)).toBe('7 seasons');
  });

  it('laat een eigen count-opmaak toe', () => {
    expect(plural('libraries.itemCount', 1200, { count: '1,200' })).toBe('1,200 items');
  });
});
