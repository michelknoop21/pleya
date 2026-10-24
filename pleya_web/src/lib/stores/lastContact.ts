/**
 * Wat deze kijker de laatste keer van de server wist.
 *
 * Als `GET /info` mislukt, is er geen servernaam en geen bibliotheeklijst. De
 * onbereikbare staat (beeld 14) wil toch zeggen wélke server er niet antwoordt,
 * sinds wanneer, en de navigatie laten staan die de gebruiker kent. Daarvoor
 * bewaart de sessie na elke geslaagde `load()` dit kleine record.
 *
 * Het is een gemak en geen bron van waarheid: zodra de server weer antwoordt,
 * wint wat hij zegt en wordt het record overschreven. Geen tokens, geen
 * titels, alleen wat de schil nodig heeft om dezelfde slots te tekenen.
 */
export const LAST_CONTACT_KEY = 'pleya.lastContact';

export interface LastContact {
  name: string;
  /** RFC 3339, het moment van de laatste geslaagde `load()`. */
  at: string;
  /** De enige capability waar `navItems` op leunt. */
  browse: boolean;
  libraries: { id: string; kind: string }[];
}

function isLastContact(value: unknown): value is LastContact {
  if (!value || typeof value !== 'object') return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v['name'] === 'string' &&
    typeof v['at'] === 'string' &&
    !Number.isNaN(Date.parse(v['at'])) &&
    typeof v['browse'] === 'boolean' &&
    Array.isArray(v['libraries']) &&
    v['libraries'].every(
      (l: unknown) =>
        !!l &&
        typeof (l as Record<string, unknown>)['id'] === 'string' &&
        typeof (l as Record<string, unknown>)['kind'] === 'string'
    )
  );
}

/** Een geweigerde opslag of een kapot record betekent: geen record. */
export function readLastContact(): LastContact | null {
  try {
    const raw = localStorage.getItem(LAST_CONTACT_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    return isLastContact(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function writeLastContact(record: LastContact): void {
  try {
    localStorage.setItem(LAST_CONTACT_KEY, JSON.stringify(record));
  } catch {
    // Opslag geweigerd: de onbereikbare staat valt dan terug op de host.
  }
}
