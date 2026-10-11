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

export const LOCALES = ['en', 'nl'] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = 'en';
export const LOCALE_STORAGE_KEY = 'pleya.locale';

// De Nederlandse catalogus is nog leeg; tot hij er is valt elke sleutel terug
// op Engels. De taal zelf staat wel al goed, zodat `<html lang>`, opslag en de
// opstartvolgorde getest kunnen worden voordat er één woord vertaald is.
const catalogues: Record<Locale, Record<string, string>> = {
  en: { ...shared, ...web },
  nl: {}
};

export type MessageKey = keyof typeof shared | keyof typeof web;

let current: Locale = DEFAULT_LOCALE;

function isLocale(value: string): value is Locale {
  return (LOCALES as readonly string[]).includes(value);
}

/** Kiest de best passende catalogus voor de talen die de browser aangeeft. */
export function pickLocale(preferred: readonly string[]): Locale {
  for (const tag of preferred) {
    const base = tag.toLowerCase().split('-')[0] ?? '';
    if (isLocale(base)) return base;
  }
  return DEFAULT_LOCALE;
}

/**
 * Bewaarde keuze wint, dan de browsertalen, dan Engels.
 *
 * Een onbekende bewaarde waarde telt niet mee: een oude of met de hand
 * aangepaste sleutel mag de browsertaal niet wegdrukken.
 */
export function resolveLocale(stored: string | null, preferred: readonly string[]): Locale {
  if (stored !== null && isLocale(stored)) return stored;
  return pickLocale(preferred);
}

function readStoredLocale(): string | null {
  try {
    return localStorage.getItem(LOCALE_STORAGE_KEY);
  } catch {
    // Opslag geweigerd: de browsertaal beslist.
    return null;
  }
}

function browserLocales(): readonly string[] {
  if (typeof navigator === 'undefined') return [];
  return navigator.languages?.length ? navigator.languages : [navigator.language];
}

function applyLocale(next: Locale): void {
  current = next;
  if (typeof document !== 'undefined') document.documentElement.lang = next;
}

/**
 * Stelt de taal vast vóór er iets rendert.
 *
 * `t()` leest een gewone variabele en geen `$state`, dus wat eenmaal getekend
 * is verandert niet meer van taal. Daarom draait dit bovenaan de layout, vóór
 * de eerste markup, en niet in `onMount`: die komt pas na het eerste renderen
 * van de kinderen en liet dan een Engelse pagina staan. Twee keer aanroepen
 * geeft hetzelfde resultaat.
 */
export function initLocale(): Locale {
  applyLocale(resolveLocale(readStoredLocale(), browserLocales()));
  return current;
}

/**
 * Bewaart de keuze en herlaadt de pagina.
 *
 * Herladen in plaats van reactief wisselen: labels die in een `<script>`-blok
 * berekend worden (`ThemePicker`, `navItems`) lezen `t()` één keer en zouden
 * anders in de oude taal blijven staan. Weigert de opslag, dan heeft herladen
 * geen zin omdat de keuze verloren gaat; de taal gaat dan alleen in het
 * geheugen om en geldt voor wat vanaf nu rendert.
 */
export function changeLocale(next: Locale, reload: () => void = () => location.reload()): void {
  if (next === current) return;
  try {
    localStorage.setItem(LOCALE_STORAGE_KEY, next);
  } catch {
    applyLocale(next);
    return;
  }
  reload();
}

const INTL_TAGS: Record<Locale, string> = { en: 'en', nl: 'nl-NL' };

/** De BCP 47-tag voor Intl: 'en' blijft 'en', 'nl' wordt 'nl-NL'. */
export function intlLocale(): string {
  return INTL_TAGS[current];
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
 * Ontbreekt de sleutel in de actieve taal, dan komt de Engelse tekst. Ontbreekt
 * hij ook daar, dan komt de sleutel zelf terug. Dat laatste is opzettelijk
 * zichtbaar: een lege string zou een gat in de UI opleveren dat niemand
 * opmerkt.
 */
export function t(key: MessageKey, params?: Record<string, string | number>): string {
  const template = catalogues[current][key] ?? catalogues.en[key] ?? key;
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
  const rule = new Intl.PluralRules(intlLocale()).select(count);
  const template =
    lookupPlural(catalogues[current], key, rule) ?? lookupPlural(catalogues.en, key, rule) ?? key;
  const merged = { count, ...params };
  return template.replace(/\{(\w+)\}/g, (whole, name: string) =>
    name in merged ? String(merged[name as keyof typeof merged]) : whole
  );
}

function lookupPlural(
  catalogue: Record<string, string>,
  key: string,
  rule: Intl.LDMLPluralRule
): string | undefined {
  return catalogue[`${key}.${rule}`] ?? catalogue[`${key}.other`];
}
