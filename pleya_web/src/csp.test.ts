// @vitest-environment node
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { describe, expect, it } from 'vitest';

import config from '../svelte.config.js';

// Kit zet de stijl van #svelte-announcer inline; de CSP laat alleen die exacte
// tekst door. Verandert een Kit-versie de tekst, dan hoort deze test als eerste
// te falen, niet de browserconsole van een gebruiker.
const kitRoot = dirname(createRequire(import.meta.url).resolve('@sveltejs/kit/package.json'));

function announcerStyle(): string {
  const source = readFileSync(join(kitRoot, 'src/core/sync/write_root.js'), 'utf8');
  const match = /id="svelte-announcer"[^>]*\sstyle="([^"]+)"/.exec(source);
  if (!match) throw new Error('announcer-stijl niet gevonden in Kit');
  return match[1];
}

describe('CSP style-src', () => {
  it('bevat de hash van de stijl die Kit nu op de announcer zet', () => {
    const hash = `sha256-${createHash('sha256').update(announcerStyle()).digest('base64')}`;
    const styleSrc = config.kit.csp.directives['style-src'];
    expect(styleSrc).toContain(hash);
    expect(styleSrc).toContain('unsafe-hashes');
  });

  it('wijst een gewijzigde stijltekst af (negatieve controle)', () => {
    const hash = `sha256-${createHash('sha256').update(announcerStyle() + ';').digest('base64')}`;
    expect(config.kit.csp.directives['style-src']).not.toContain(hash);
  });
});
