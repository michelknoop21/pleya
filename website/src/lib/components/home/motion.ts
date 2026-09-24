import 'lenis/dist/lenis.css';

/**
 * Homepage choreography. The page is complete without it: motion only runs
 * when the visitor has not asked for reduced motion, and every tween starts
 * from the finished static layout. Returns a cleanup for onMount.
 */
export async function startHomeMotion(root: HTMLElement): Promise<() => void> {
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

    // Hero: the title rises, then the Apple TV screen switches on like a projector.
    const phone = q('[data-phone]');
    gsap
      .timeline({ defaults: { ease: 'expo.out' } })
      .from(root.querySelectorAll('.hero-title .ln > span'), { yPercent: 110, duration: 1.15, stagger: 0.12 })
      .from(root.querySelectorAll('.hero-row > *, .works'), { y: 18, autoAlpha: 0, duration: 0.8, stagger: 0.08 }, '-=0.75')
      .fromTo(
        q('[data-screen]'),
        { clipPath: 'inset(49.6% 0% 49.6% 0% round 12px)', filter: 'brightness(2.4)' },
        { clipPath: 'inset(0% 0% 0% 0% round 12px)', filter: 'brightness(1)', duration: 1.3, ease: 'expo.inOut', clearProps: 'filter' },
        '-=0.6',
      )
      .from(q('.hero .spill'), { autoAlpha: 0, duration: 1.4, ease: 'power2.out' }, '<0.3')
      .from(phone, { yPercent: 16, autoAlpha: 0, duration: 1 }, '<0.5');
    gsap.to(phone, { y: -80, ease: 'none', scrollTrigger: { trigger: q('[data-stage]'), start: 'top 60%', end: 'bottom top', scrub: true } });

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

    // One library: the sources light up one by one, ending on what happens to them.
    gsap.fromTo(
      root.querySelectorAll('[data-source]'),
      { color: 'rgba(244,241,236,.22)' },
      {
        color: (_i: number, el: Element) => (el.classList.contains('into') ? '#ffb020' : '#f4f1ec'),
        stagger: 0.5,
        ease: 'none',
        scrollTrigger: { trigger: q('.sources'), start: 'top 80%', end: 'top 35%', scrub: true },
      },
    );
    gsap.from(q('.unified-shots .phone'), { yPercent: 20, autoAlpha: 0, duration: 1, ease: 'expo.out', scrollTrigger: { trigger: q('.unified-shots'), start: 'top 75%', once: true } });

    // Apple TV reel: on wide screens the section pins and the frames travel
    // sideways like film through a gate. Narrow screens keep native swiping.
    const wide = gsap.matchMedia();
    wide.add('(min-width: 900px)', () => {
      const track = q('[data-track]')!;
      const viewport = q('[data-reel]')!;
      viewport.style.overflowX = 'hidden';
      const distance = () => track.scrollWidth - viewport.clientWidth;
      gsap.to(track, {
        x: () => -distance(),
        ease: 'none',
        scrollTrigger: { trigger: q('#reel'), start: 'top top', end: () => '+=' + distance(), pin: true, scrub: 0.6, invalidateOnRefresh: true },
      });
      return () => {
        viewport.style.overflowX = '';
      };
    });

    gsap.from(root.querySelectorAll('.devices-stage .phone'), {
      y: 90,
      autoAlpha: 0,
      duration: 1.1,
      ease: 'expo.out',
      stagger: 0.12,
      scrollTrigger: { trigger: q('.devices-stage'), start: 'top 70%', once: true },
    });

    // Supporting content follows its heading, one group at a time.
    for (const [trigger, targets] of [
      ['.trio', '.trio > div'],
      ['.share-steps', '.share-steps li'],
      ['.routes', '.routes > div'],
      ['.more .cols', '.more .cols > div'],
      ['.open .cols', '.open .cols > div, .links'],
      ['.faq-list', '.faq details'],
      ['.final', '.final h2, .final p, .final .actions'],
    ]) {
      gsap.from(root.querySelectorAll(targets), { y: 28, autoAlpha: 0, duration: 0.85, ease: 'power3.out', stagger: 0.08, scrollTrigger: { trigger: q(trigger), start: 'top 82%', once: true } });
    }

    const refresh = () => ScrollTrigger.refresh();
    document.fonts?.ready.then(refresh);
    window.addEventListener('load', refresh);

    return () => {
      wide.revert();
      window.removeEventListener('load', refresh);
      gsap.ticker.remove(tick);
      lenis.destroy();
    };
  });

  return () => mm.revert();
}
