import { describe, expect, it } from 'vitest';

import { LOCALES, pickLocale, plural, t } from './index';

describe('taalkeuze', () => {
  it('kiest de catalogus die bij de browsertaal past', () => {
    expect(pickLocale(['en-GB', 'nl'])).toBe('en');
    expect(pickLocale(['nl-NL'])).toBe('en'); // nog geen Nederlandse catalogus
  });

  it('valt terug op Engels bij een taal die er niet is', () => {
    expect(pickLocale(['ja'])).toBe('en');
    expect(pickLocale([])).toBe('en');
  });

  it('levert vandaag één catalogus, maar de architectuur draagt er meer', () => {
    expect([...LOCALES]).toEqual(['en']);
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
