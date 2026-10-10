/**
 * Themakeuze, met dezelfde vier standen als de app: OLED, dark, light en
 * system. Het vertrekpunt wijkt af: de app start op OLED
 * (`ThemeProvider._themeMode = settings.ThemeMode.oled`), web op dark, omdat
 * de northstar en de diepte van designsysteem v2 op #141414 getekend zijn.
 * Een bewaarde keuze wint altijd, ook een eerder bewaarde OLED.
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
  mode = $state<ThemeMode>('dark');
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
      // Opslag geweigerd: dark blijft staan.
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
