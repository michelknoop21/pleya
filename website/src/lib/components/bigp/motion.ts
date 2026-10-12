import { startPageMotion } from '$lib/motion';
import { sendCue } from './cue';

/**
 * Big P page choreography on top of the shared page motion. The page is complete without it:
 * every tween starts from the finished layout, and the cues only make Big P react to what
 * scrolls past him.
 */
export const startBigPMotion = (root: HTMLElement) =>
  startPageMotion(root, ({ gsap, ScrollTrigger, q }) => {
    gsap
      .timeline({ defaults: { ease: 'expo.out' } })
      .from(root.querySelectorAll('.bp-hero .ln > span'), { yPercent: 110, duration: 1.15, stagger: 0.12 })
      .from(root.querySelectorAll('.bp-hero .eyebrow, .bp-hero .lede, .bp-hero .actions, .bp-hero .cta-note'), { y: 18, opacity: 0, duration: 0.8, stagger: 0.08 }, '-=0.8')
      .from(root.querySelectorAll('.bp-hero .orb'), { opacity: 0, duration: 1.6, ease: 'power2.out' }, 0);

    // Cards and panels come up as they enter; in the bento each one also asks for Big P's arm.
    root.querySelectorAll<HTMLElement>('.bento .grid, .ask .demo, .confirm .stage, .providers').forEach((group) => {
      gsap.from(group.children, { y: 48, opacity: 0, duration: 1, ease: 'expo.out', stagger: 0.09, scrollTrigger: { trigger: group, start: 'top 92%', once: true } });
    });

    const bento = q('.bento');
    if (bento) {
      root.querySelectorAll<HTMLElement>('[data-card]').forEach((card) => {
        ScrollTrigger.create({ trigger: card, start: 'top 62%', end: 'bottom 62%', onToggle: (self) => self.isActive && sendCue(bento, { name: 'card', el: card }) });
      });
      ScrollTrigger.create({ trigger: bento, start: 'top bottom', end: 'bottom top', onLeave: () => sendCue(bento, { name: 'leave' }), onLeaveBack: () => sendCue(bento, { name: 'leave' }) });
    }
    for (const sel of ['.confirm', '.providers']) {
      const el = q(sel);
      if (el) ScrollTrigger.create({ trigger: el, start: 'top 65%', once: true, onEnter: () => sendCue(el, { name: 'enter' }) });
    }
  });
