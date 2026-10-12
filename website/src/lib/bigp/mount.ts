import { CORE, LATER, type Pose } from './layers';
import { register, wake } from './loop';
import { preload } from './markup';
import { BigP, type Options } from './rig';

/**
 * Put a Big P in `host` and keep him running while he is in view. The poses beyond the rest
 * render load once the page is idle.
 */
export function mount(host: HTMLElement, opts: Options = {}): { bigp: BigP; destroy: () => void } {
  const bigp = new BigP(host, opts);
  const unregister = register(bigp);
  const seen = new IntersectionObserver(
    ([entry]) => {
      bigp.visible = entry.isIntersecting;
      wake();
    },
    { rootMargin: '120px' },
  );
  seen.observe(host);
  const idle = window.requestIdleCallback ?? ((fn: () => void) => setTimeout(fn, 400));
  idle(() => {
    for (const pose of Object.keys(LATER) as Pose[]) if (pose !== 'wijzen_links' || opts.facing === -1) void bigp.ensure(pose).catch(() => {});
  });
  return {
    bigp,
    destroy() {
      seen.disconnect();
      unregister();
      bigp.destroy();
    },
  };
}

/** Resolves once the layers of the rest pose are in: the rig can replace the still image without a gap. */
export const coreLoaded = (): Promise<unknown> =>
  Promise.all([CORE.rest, CORE.browL, CORE.browR, CORE.mouths.rest, ...Object.values(CORE.legs).flatMap((l) => [l.upper, l.lower])].map(preload)).catch(() => {});
