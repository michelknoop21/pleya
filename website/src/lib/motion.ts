import 'lenis/dist/lenis.css';

export type Kit = {
  gsap: typeof import('gsap').gsap;
  ScrollTrigger: typeof import('gsap/ScrollTrigger').ScrollTrigger;
  q: (selector: string) => HTMLElement | null;
};

/** Page choreography shared by every marketing page. Runs only without a reduced-motion preference. */
export async function startPageMotion(root: HTMLElement, extra?: (kit: Kit) => void | (() => void)): Promise<() => void> {
  const [{ gsap }, { ScrollTrigger }, { SplitText }, { default: Lenis }] = await Promise.all([
    import('gsap'),
    import('gsap/ScrollTrigger'),
    import('gsap/SplitText'),
    import('lenis'),
  ]);
  gsap.registerPlugin(ScrollTrigger, SplitText);
  const q = (selector: string) => root.querySelector<HTMLElement>(selector);
  const mm = gsap.matchMedia();

  mm.add('(prefers-reduced-motion: no-preference)', () => {
    const lenis = new Lenis();
    lenis.on('scroll', ScrollTrigger.update);
    const tick = (time: number) => lenis.raf(time * 1000);
    gsap.ticker.add(tick);
    gsap.ticker.lagSmoothing(0);

    // Large headings: words rise out of a mask. SplitText keeps an aria-label
    // with the whole heading and hides the split words from assistive tech.
    root.querySelectorAll<HTMLElement>('[data-split]').forEach((el) => {
      SplitText.create(el, {
        type: 'words',
        mask: 'words',
        autoSplit: true,
        onSplit: (self) =>
          gsap.from(self.words, { yPercent: 105, duration: 0.95, ease: 'expo.out', stagger: 0.05, scrollTrigger: { trigger: el, start: 'top 85%', once: true } }),
      });
    });

    // Supporting content follows its heading: the direct children of a
    // [data-reveal] container come up one at a time, decorative ones excluded.
    root.querySelectorAll<HTMLElement>('[data-reveal]').forEach((el) => {
      const kids = [...el.children].filter((c) => !c.hasAttribute('aria-hidden'));
      if (kids.length)
        gsap.from(kids, { y: 28, autoAlpha: 0, duration: 0.85, ease: 'power3.out', stagger: 0.08, scrollTrigger: { trigger: el, start: 'top 82%', once: true } });
    });

    const undoExtra = extra?.({ gsap, ScrollTrigger, q });
    // The reveals above are created before a page's own pins (such as the
    // homepage reel); sorting by start lets refresh add the pin distance to
    // every trigger further down the page.
    ScrollTrigger.sort();
    const refresh = () => ScrollTrigger.refresh();
    document.fonts?.ready.then(refresh);
    window.addEventListener('load', refresh);

    return () => {
      undoExtra?.();
      window.removeEventListener('load', refresh);
      gsap.ticker.remove(tick);
      lenis.destroy();
    };
  });

  return () => mm.revert();
}

/** Svelte action: `use:pageMotion` or `use:pageMotion={startHomeMotion}`. Handles the async start/teardown race. */
export function pageMotion(node: HTMLElement, start: (root: HTMLElement) => Promise<() => void> = startPageMotion) {
  let stop: (() => void) | undefined;
  let dead = false;
  start(node).then((cleanup) => (dead ? cleanup() : (stop = cleanup)));
  return {
    destroy() {
      dead = true;
      stop?.();
    },
  };
}
