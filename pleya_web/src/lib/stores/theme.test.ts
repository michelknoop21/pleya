import { describe, expect, it } from 'vitest';

import { isThemeMode, resolvePalette, THEME_MODES } from './theme.svelte';

describe('themakeuze', () => {
  it('kent dezelfde vier standen als de app', () => {
    expect([...THEME_MODES]).toEqual(['oled', 'dark', 'light', 'system']);
  });

  it('vertaalt system naar de systeemvoorkeur', () => {
    expect(resolvePalette('system', true)).toBe('dark');
    expect(resolvePalette('system', false)).toBe('light');
  });

  it('laat een expliciete keuze staan, wat het systeem ook zegt', () => {
    expect(resolvePalette('oled', false)).toBe('oled');
    expect(resolvePalette('light', true)).toBe('light');
  });

  it('herkent geen onzin als stand', () => {
    expect(isThemeMode('neon')).toBe(false);
    expect(isThemeMode('oled')).toBe(true);
  });
});
