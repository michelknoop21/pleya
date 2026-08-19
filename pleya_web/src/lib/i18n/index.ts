/**
 * Taal, vanaf de eerste component.
 *
 * De architectuur is locale-aware vanaf dag één (onderdeel 5.7 van het
 * PS-3W-voorstel): elke zichtbare tekst gaat door `t()`, ook nu er één catalogus
 * is. Een tweede taal is dan een bestand erbij en geen herbouw van de UI.
 *
 * De Engelse catalogus bestaat uit twee helften: `shared` komt uit
 * `lib/i18n/en.i18n.json` en is dus dezelfde bron als de app, `web` bevat wat
 * alleen de webclient kent.
 */
import { shared } from './shared';
import { web } from './web';

export const LOCALES = ['en'] as const;
export type Locale = (typeof LOCALES)[number];

const catalogues: Record<Locale, Record<string, string>> = {
  en: { ...shared, ...web }
};

export type MessageKey = keyof typeof shared | keyof typeof web;

let current: Locale = 'en';

/** Kiest de best passende catalogus voor de talen die de browser aangeeft. */
export function pickLocale(preferred: readonly string[]): Locale {
  for (const tag of preferred) {
    const base = tag.toLowerCase().split('-')[0];
    const match = LOCALES.find((l) => l === base);
    if (match) return match;
  }
  return 'en';
}

export function setLocale(locale: Locale): void {
  current = locale;
}

export function locale(): Locale {
  return current;
}

/**
 * Vertaalt een sleutel en vult `{naam}`-plaatshouders in.
 *
 * Een ontbrekende sleutel geeft de sleutel zelf terug. Dat is opzettelijk
 * zichtbaar: een lege string zou een gat in de UI opleveren dat niemand
 * opmerkt.
 */
export function t(key: MessageKey, params?: Record<string, string | number>): string {
  const template = catalogues[current][key] ?? key;
  if (!params) return template;
  return template.replace(/\{(\w+)\}/g, (whole, name: string) =>
    name in params ? String(params[name]) : whole
  );
}

/**
 * Vertaalt een sleutel die per aantal verschilt.
 *
 * De vorm wordt door `Intl.PluralRules` van de actieve taal gekozen, niet door
 * een `count === 1`-test. Engels heeft twee vormen en Nederlands ook, maar
 * Pools heeft er drie en Japans één; die keuze nu bij de taal leggen scheelt
 * dat de UI later opnieuw wordt gebouwd.
 */
export function plural(
  key: string,
  count: number,
  params?: Record<string, string | number>
): string {
  const rule = new Intl.PluralRules(current).select(count);
  const catalogue = catalogues[current];
  const template = catalogue[`${key}.${rule}`] ?? catalogue[`${key}.other`] ?? key;
  const merged = { count, ...params };
  return template.replace(/\{(\w+)\}/g, (whole, name: string) =>
    name in merged ? String(merged[name as keyof typeof merged]) : whole
  );
}
