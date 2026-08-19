import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const CONTRACT = resolve(import.meta.dirname, '../../../../docs/pleya-protocol/v1/openapi.yaml');
const GENERATED = resolve(import.meta.dirname, 'schema.d.ts');

/**
 * Acceptatiecriterium 5: de gegenereerde client komt aantoonbaar uit
 * openapi.yaml.
 *
 * Deze test doet de goedkope helft — de hash die de generator in de kop
 * schrijft moet die van het contract van vandaag zijn. De dure helft doet
 * `scripts/check-api-types.sh`: opnieuw genereren en byte-voor-byte
 * vergelijken. Samen zijn ze wat de codegen-sectie van `scripts/ci_checks.sh`
 * voor Dart doet, alleen scherper dan een tijdstempel.
 */
describe('de gegenereerde API-client', () => {
  const generated = readFileSync(GENERATED, 'utf8');

  it('noemt zijn bron in de kop', () => {
    expect(generated).toContain('docs/pleya-protocol/v1/openapi.yaml');
  });

  it('draagt de hash van het contract dat er nu ligt', () => {
    const actual = createHash('sha256').update(readFileSync(CONTRACT)).digest('hex');
    const recorded = /bron-sha256: ([0-9a-f]{64})/.exec(generated)?.[1];

    expect(recorded).toBeDefined();
    expect(recorded).toBe(actual);
  });

  it('kent elk endpoint dat het contract beschrijft', () => {
    const contract = readFileSync(CONTRACT, 'utf8');
    const paths = [...contract.matchAll(/^ {2}(\/[a-z0-9{}_\-/]+):$/gim)].map((m) => m[1]);

    expect(paths.length).toBeGreaterThan(10);
    for (const path of paths) {
      expect(generated).toContain(`"${path}"`);
    }
  });

  it('kent geen endpoint dat het contract niet beschrijft', () => {
    // Het gegenereerde bestand is uitvoer, dus dit meet vooral dat er niemand
    // met de hand een pad heeft bijgeschreven.
    const contract = readFileSync(CONTRACT, 'utf8');
    const generatedPaths = [...generated.matchAll(/^ {4}"(\/[a-z0-9{}_\-/]+)": \{$/gim)].map(
      (m) => m[1]
    );

    expect(generatedPaths.length).toBeGreaterThan(10);
    for (const path of generatedPaths) {
      expect(contract).toContain(`  ${path}:`);
    }
  });
});
