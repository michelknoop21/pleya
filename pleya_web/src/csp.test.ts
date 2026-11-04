// @vitest-environment node
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { csp } from '../csp.ts';
import { kitOptions } from '../vite.config.ts';

// Kit zet de stijl van #svelte-announcer inline; de CSP laat alleen die exacte
// tekst door. Verandert een Kit-versie de tekst, dan hoort deze test als eerste
// te falen, niet de browserconsole van een gebruiker.
const kitRoot = dirname(createRequire(import.meta.url).resolve('@sveltejs/kit/package.json'));

function announcerStyle(): string {
  const source = readFileSync(join(kitRoot, 'src/runtime/components/root.svelte'), 'utf8');
  const match = /id="svelte-announcer"[^>]*\sstyle="([^"]+)"/.exec(source);
  if (!match) throw new Error('announcer-stijl niet gevonden in Kit');
  return match[1] ?? '';
}

const styleSrc = csp.directives?.['style-src'] ?? [];

describe('CSP style-src', () => {
  it('bevat de hash van de stijl die Kit nu op de announcer zet', () => {
    const hash = `sha256-${createHash('sha256').update(announcerStyle()).digest('base64')}`;
    expect(styleSrc).toContain(hash);
    expect(styleSrc).toContain('unsafe-hashes');
  });

  it('wijst een gewijzigde stijltekst af (negatieve controle)', () => {
    const hash = `sha256-${createHash('sha256').update(announcerStyle() + ';').digest('base64')}`;
    expect(styleSrc).not.toContain(hash);
  });
});

// De speler (S13.2, S18.3) vraagt precies één verruiming: media-src blob:,
// voor de MediaSource-URL van hls.js en de WebVTT-ondertitel als object-URL.
// Een worker uit een blob:-URL is er niet bij, want hls.js draait zonder
// worker; script-src en worker-src blijven dus dicht.
const directives = (csp.directives ?? {}) as Record<string, string[] | undefined>;

describe('CSP voor de speler', () => {
  it('staat media alleen van de eigen origin en blob: toe', () => {
    expect(directives['media-src']).toEqual(['self', 'blob:']);
  });

  it('opent geen worker of script voor blob: en geen externe host', () => {
    expect(directives['worker-src']).toBeUndefined();
    expect(directives['child-src']).toBeUndefined();
    expect(directives['script-src']).toEqual(['self']);
    expect(directives['connect-src']).toEqual(['self']);
  });

  it('negatieve controle: een verruiming naar een host of data: zou de toets laten falen', () => {
    const widened = ['self', 'blob:', 'data:'];
    expect(widened).not.toEqual(directives['media-src']);
  });

  it('hls.js draait zonder worker, anders zou worker-src blob: nodig zijn', async () => {
    const { hlsConfig } = await import('./lib/player/hlsEngine');
    expect(hlsConfig(async () => null)['enableWorker']).toBe(false);
  });
});

// De CSP staat in csp.ts, maar de build gebruikt wat vite.config.ts aan de
// Kit-plugin geeft. Zonder deze toets kan een configwijziging `csp` laten
// vallen terwijl elke andere toets groen blijft en de bundel zonder policy
// uitgaat.
describe('CSP in de build-config', () => {
  it('geeft precies het csp-object uit csp.ts aan de Kit-opties', () => {
    expect(kitOptions.csp).toBe(csp);
    expect(kitOptions.csp?.mode).toBe('hash');
  });

  it('geeft die Kit-opties aan de sveltekit-plugin', () => {
    const source = readFileSync(join(import.meta.dirname, '../vite.config.ts'), 'utf8');
    expect(source).toMatch(/sveltekit\(kitOptions\)/);
  });
});
