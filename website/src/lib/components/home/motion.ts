import { startPageMotion } from '$lib/motion';

/**
 * Homepage choreography on top of the shared page motion. The page is complete
 * without it: every tween starts from the finished static layout, and each
 * block only runs when its section is present.
 */
export const startHomeMotion = (root: HTMLElement) =>
  startPageMotion(root, ({ gsap, q }) => {
    // Hero: the title rises, then the Apple TV screen switches on like a projector.
    if (q('[data-screen]')) {
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
    }

    // One library: the sources light up one by one, ending on what happens to them.
    if (q('.sources')) {
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
    }

    // Apple TV reel: on wide screens the section pins and the frames travel
    // sideways like film through a gate. Narrow screens keep native swiping.
    const wide = gsap.matchMedia();
    const track = q('[data-track]');
    const viewport = q('[data-reel]');
    if (track && viewport) {
      wide.add('(min-width: 900px)', () => {
        viewport.style.overflowX = 'hidden';
        const distance = () => track.scrollWidth - viewport.clientWidth;
        gsap.to(track, {
          x: () => -distance(),
          ease: 'none',
          scrollTrigger: { trigger: q('#reel'), start: 'top top', end: () => '+=' + distance(), pin: true, scrub: 0.6, invalidateOnRefresh: true, refreshPriority: 1 },
        });
        return () => {
          viewport.style.overflowX = '';
        };
      });
    }

    if (q('.devices-stage')) {
      gsap.from(root.querySelectorAll('.devices-stage .phone'), {
        y: 90,
        autoAlpha: 0,
        duration: 1.1,
        ease: 'expo.out',
        stagger: 0.12,
        scrollTrigger: { trigger: q('.devices-stage'), start: 'top 70%', once: true },
      });
    }

    return () => wide.revert();
  });
