// One requestAnimationFrame loop for every Big P on the page. It stops while no figure is
// in view or the tab is hidden, and nothing here runs at import time, so prerendering is safe.

export type Ticker = { visible: boolean; tick(dt: number, reduced: boolean): void };

const all = new Set<Ticker>();
let raf = 0;
let last = 0;
let reducedQuery: MediaQueryList | undefined;

const anyVisible = () => {
  for (const t of all) if (t.visible) return true;
  return false;
};

function frame(now: number) {
  raf = 0;
  if (document.hidden || !anyVisible()) return;
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  const reduced = reducedQuery?.matches ?? false;
  for (const t of all) if (t.visible) t.tick(dt, reduced);
  raf = requestAnimationFrame(frame);
}

/** Start the loop if it is idle and there is something to draw. */
export function wake() {
  if (raf || document.hidden || !anyVisible()) return;
  last = performance.now();
  raf = requestAnimationFrame(frame);
}

export function register(t: Ticker): () => void {
  if (!all.size) {
    reducedQuery = matchMedia('(prefers-reduced-motion: reduce)');
    document.addEventListener('visibilitychange', wake);
  }
  all.add(t);
  wake();
  return () => {
    all.delete(t);
    if (all.size) return;
    document.removeEventListener('visibilitychange', wake);
    cancelAnimationFrame(raf);
    raf = 0;
  };
}

export const prefersReducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
