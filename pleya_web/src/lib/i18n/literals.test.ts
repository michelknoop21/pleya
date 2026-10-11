import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { describe, expect, it } from 'vitest';

const SRC = resolve(__dirname, '../..');
const ATTR = /\b(aria-label|title|placeholder|alt)="([^"]*)"/g;

/** Alle `.svelte`-bestanden onder src, behalve de dev-galerij. */
function svelteFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      return relative(SRC, full).split(sep).join('/') === 'routes/dev' ? [] : svelteFiles(full);
    }
    return full.endsWith('.svelte') ? [full] : [];
  });
}

/**
 * Letterlijke waarden van tekstattributen. Een waarde telt als letterlijk
 * zodra er na het weghalen van `{...}`-expressies nog letters overblijven;
 * `alt=""` (decoratief) en pure expressies zijn toegestaan.
 */
export function findLiterals(source: string): string[] {
  const hits: string[] = [];
  for (const match of source.matchAll(ATTR)) {
    const rest = (match[2] ?? '').replace(/\{[^}]*\}/g, '');
    if (/\p{L}/u.test(rest)) hits.push(match[0]);
  }
  return hits;
}

describe('geen letterlijke UI-tekst in attributen', () => {
  it('herkent een letterlijke waarde (negatieve controle)', () => {
    expect(findLiterals('<button aria-label="Sluiten">')).toEqual(['aria-label="Sluiten"']);
    expect(findLiterals('<img alt="" />')).toEqual([]);
    expect(findLiterals('<a title={t(\'x\')} aria-label="{label}">')).toEqual([]);
  });

  it('heeft in geen enkel component een aria-label, title, placeholder of alt als letterlijke tekst', () => {
    const files = svelteFiles(SRC);
    expect(files.length).toBeGreaterThan(0);
    const offenders = files.flatMap((file) =>
      findLiterals(readFileSync(file, 'utf8')).map((hit) => `${relative(SRC, file)}: ${hit}`)
    );
    expect(offenders).toEqual([]);
  });
});
