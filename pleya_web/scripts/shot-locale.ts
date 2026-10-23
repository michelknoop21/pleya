/**
 * De vlag `--locale nl|en` voor de opnamescripts.
 *
 * De taal komt in de app uit de bewaarde keuze en anders uit de browser
 * (`resolveLocale`). Een opname in een bepaalde taal zet dus de browsertaal via
 * Playwright (`locale` op de context: `navigator.languages` en Accept-Language)
 * en wist `pleya.locale` vóór elk script van de pagina draait. Anders zou een
 * keuze uit een eerdere ronde in dezelfde opslag het winnen van de vlag.
 */
import type { BrowserContext, BrowserContextOptions } from '@playwright/test';

export type ShotLocale = 'nl' | 'en';

const CONTEXT_LOCALES: Record<ShotLocale, string> = { nl: 'nl-NL', en: 'en-US' };

/** Haalt `--locale x` uit de argumenten; wat overblijft zijn de positionele. */
export function parseLocaleFlag(argv: readonly string[]): {
  locale?: ShotLocale;
  rest: string[];
} {
  const rest = [...argv];
  const at = rest.indexOf('--locale');
  if (at < 0) return { rest };
  const value = rest.splice(at, 2)[1];
  if (value !== 'nl' && value !== 'en') {
    throw new Error(`--locale verwacht nl of en, kreeg ${value ?? 'niets'}`);
  }
  return { locale: value, rest };
}

/** De contextopties voor die taal; zonder vlag geen locale (systeemstandaard). */
export function localeContextOptions(locale?: ShotLocale): BrowserContextOptions {
  return locale ? { locale: CONTEXT_LOCALES[locale] } : {};
}

/** Wist de bewaarde taalkeuze bij elke navigatie, vóór de app hem leest. */
export async function forgetStoredLocale(context: BrowserContext): Promise<void> {
  await context.addInitScript(() => {
    try {
      localStorage.removeItem('pleya.locale');
    } catch {
      // Opslag geweigerd: dan is er ook niets bewaard dat de vlag overstemt.
    }
  });
}
