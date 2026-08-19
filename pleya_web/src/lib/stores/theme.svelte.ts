/**
 * Themakeuze, met dezelfde vier standen en dezelfde standaard als de app:
 * OLED, dark, light en system, met OLED als vertrekpunt
 * (`ThemeProvider._themeMode = settings.ThemeMode.oled`).
 *
 * `system` bestaat in de app als "volg het toestel", en die vertaalt op web
 * naar `prefers-color-scheme`. De attribuutwaarde op <html> is altijd een van
 * de drie echte paletten, want CSS kent geen "systeem".
 */
export const THEME_MODES = ['oled', 'dark', 'light', 'system'] as const;
export type ThemeMode = (typeof THEME_MODES)[number];

const STORAGE_KEY = 'pleya.theme';

export function isThemeMode(value: string): value is ThemeMode {
  return (THEME_MODES as readonly string[]).includes(value);
}

export function resolvePalette(mode: ThemeMode, prefersDark: boolean): 'oled' | 'dark' | 'light' {
  if (mode === 'system') return prefersDark ? 'dark' : 'light';
  return mode;
}

class ThemeState {
  mode = $state<ThemeMode>('oled');
  prefersDark = $state(true);

  get palette(): 'oled' | 'dark' | 'light' {
    return resolvePalette(this.mode, this.prefersDark);
  }

  /** Leest de bewaarde keuze en begint te luisteren naar de systeemvoorkeur. */
  start(): () => void {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored && isThemeMode(stored)) this.mode = stored;
    } catch {
      // Opslag geweigerd: OLED blijft staan.
    }

    if (typeof matchMedia !== 'function') return () => {};
    const query = matchMedia('(prefers-color-scheme: dark)');
    this.prefersDark = query.matches;
    const onChange = (event: MediaQueryListEvent) => {
      this.prefersDark = event.matches;
    };
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }

  set(mode: ThemeMode): void {
    this.mode = mode;
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {
      // niets te doen
    }
  }
}

export const theme = new ThemeState();
