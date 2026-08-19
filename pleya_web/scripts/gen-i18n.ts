/**
 * Haalt de gedeelde strings uit de i18n-bron van de app.
 *
 * De bron is `lib/i18n/en.i18n.json`, dezelfde die `slang` voor de Flutter-app
 * leest. Wat hier binnenkomt is een expliciete selectie: alleen sleutels die op
 * web dezelfde betekenis hebben. Web-eigen teksten staan los in
 * `src/lib/i18n/web.ts`, zodat een sleutel nooit stil van bron wisselt.
 *
 * Draaien: bun run scripts/gen-i18n.ts
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, '../../lib/i18n/en.i18n.json');
const target = resolve(here, '../src/lib/i18n/shared.ts');

/** Precies de sleutels die web overneemt. Volgorde is de uitvoervolgorde. */
const KEYS = [
  'states.emptyTitle',
  'states.errorTitle',
  'states.offlineTitle',
  'states.offlineMessage',
  'common.retry',
  'common.cancel',
  'common.close',
  'common.clear',
  'common.search',
  'common.home',
  'common.settings',
  'common.back',
  'common.error',
  'common.unknown',
  'common.logout',
  'common.viewAll',
  'navigation.libraries',
  'search.tryDifferentTerm',
  'search.searchYourMedia',
  'search.enterTitleActorOrKeyword',
  'search.filters.all',
  'search.filters.movies',
  'search.filters.shows',
  'search.filters.episodes',
  'auth.signIn',
  'settings.theme',
  'settings.language'
] as const;

const raw = JSON.parse(readFileSync(source, 'utf8')) as Record<string, unknown>;

function pick(path: string): string {
  let node: unknown = raw;
  for (const part of path.split('.')) {
    if (typeof node !== 'object' || node === null) {
      throw new Error(`sleutel ${path} bestaat niet in ${source}`);
    }
    node = (node as Record<string, unknown>)[part];
  }
  if (typeof node !== 'string') throw new Error(`sleutel ${path} is geen tekst`);
  return node;
}

const lines = KEYS.map((key) => `  ${JSON.stringify(key)}: ${JSON.stringify(pick(key))}`);

const out = `// Gegenereerd uit lib/i18n/en.i18n.json, de i18n-bron van de app.
// Niet met de hand wijzigen; draai: bun run scripts/gen-i18n.ts
export const shared = {
${lines.join(',\n')}
} as const;

export type SharedKey = keyof typeof shared;
`;

writeFileSync(target, out);
console.log(`→ ${target} (${KEYS.length} sleutels)`);
