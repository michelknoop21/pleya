/**
 * Een ingebed spoor uit een groot MKV kost de server minuten: Matroska heeft
 * geen tabel naar de ondertitelblokken, dus ffmpeg leest het hele bestand. De
 * aanvraag blijft kort en antwoordt `503` met `Retry-After` zolang het spoor
 * niet klaar is. Herhalen sluit aan op de lopende extractie, of start hem zodra
 * de ene werker vrij is. Alleen dat antwoord wordt herhaald; alles anders
 * (`401`, `404`, `502`, een afgebroken verbinding) is de uitkomst.
 */

/** De extractiegrens van tien minuten, plus ruimte om het resultaat op te halen. */
export const SUBTITLE_RETRY_LIMIT_MS = 11 * 60 * 1000;
const DEFAULT_RETRY_AFTER_SECONDS = 5;
const MAX_RETRY_AFTER_SECONDS = 60;

export class SubtitleNotReadyError extends Error {
  constructor(readonly retryAfterMs: number) {
    super('Subtitle is still being prepared');
  }
}

/** Alleen seconden: het contract kent `Retry-After: 5`, en 0 mag geen hete lus worden. */
export function retryAfterMs(header: string | null): number {
  const seconds = /^\d+$/.test(header?.trim() ?? '') ? Number(header) : DEFAULT_RETRY_AFTER_SECONDS;
  return Math.min(Math.max(seconds, 1), MAX_RETRY_AFTER_SECONDS) * 1000;
}

function pause(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) return reject(new DOMException('Aborted', 'AbortError'));
    const stop = () => { clearTimeout(timer); reject(new DOMException('Aborted', 'AbortError')); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', stop); resolve(); }, ms);
    signal.addEventListener('abort', stop, { once: true });
  });
}

/** Herhaalt `load` tot er een uitkomst is, `outer` afbreekt of de grens verstrijkt. */
export async function subtitleTextWhenReady(
  load: (signal: AbortSignal) => Promise<string>,
  outer: AbortSignal
): Promise<string> {
  const controller = new AbortController();
  const stop = () => controller.abort();
  if (outer.aborted) stop();
  outer.addEventListener('abort', stop, { once: true });
  const limit = setTimeout(stop, SUBTITLE_RETRY_LIMIT_MS);
  try {
    for (;;) {
      try {
        return await load(controller.signal);
      } catch (error) {
        if (!(error instanceof SubtitleNotReadyError)) throw error;
        await pause(error.retryAfterMs, controller.signal);
      }
    }
  } finally {
    clearTimeout(limit);
    outer.removeEventListener('abort', stop);
  }
}
