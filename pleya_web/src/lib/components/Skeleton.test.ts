import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { render } from '@testing-library/svelte';

import Skeleton from './Skeleton.svelte';

/*
 * De glans valt weg onder `prefers-reduced-motion`. jsdom past geen
 * mediaqueries op stylesheets toe en draait geen animaties, dus dat deel is
 * hier niet te testen; het staat als regel in de stijl van Skeleton.svelte.
 */
describe('Skeleton', () => {
  it.each(['block', 'line', 'title', 'hero'] as const)('tekent een %s als één decoratief vlak', (kind) => {
    const { container } = render(Skeleton, { props: { kind } });
    const el = container.querySelector('.skel');
    expect(el).toHaveClass(`skel--${kind}`);
    expect(el).toHaveAttribute('aria-hidden', 'true');
  });

  it('bouwt een kaart op als beeld, titel en metaregel, zoals MediaCard', () => {
    const { container } = render(Skeleton, { props: { kind: 'card' } });
    const card = container.querySelector('.skc');
    expect(card).toHaveAttribute('aria-hidden', 'true');
    expect(card?.querySelectorAll('.skel')).toHaveLength(3);
    expect(card?.querySelector('.skc__art')).not.toHaveClass('skc__art--wide');
  });

  it('volgt de brede vorm van een afleveringskaart', () => {
    const { container } = render(Skeleton, { props: { kind: 'card', shape: 'wide' } });
    expect(container.querySelector('.skc__art')).toHaveClass('skc__art--wide');
  });

  it('zet een afwijkende breedte via een stijl-eigenschap, niet via een klasse per maat', () => {
    const { container } = render(Skeleton, { props: { kind: 'line', width: '40%' } });
    expect((container.querySelector('.skel') as HTMLElement).style.width).toBe('40%');
  });

  it('heeft geen tekst, dus niets dat een schermlezer zou voorlezen', () => {
    const { container } = render(Skeleton, { props: { kind: 'card' } });
    expect(container.textContent?.trim()).toBe('');
  });

  /*
   * jsdom past de componentstijl niet toe (getComputedStyle geeft daar geen
   * radius of verhouding), dus de vorm zelf staat in de opnamen. Wat hier wel
   * vast te leggen is: skelet en Hero lezen dezelfde tokens, en de oude
   * rand-tot-randvorm met --hero-min-h en 62dvh is uit allebei weg.
   */
  it('geeft het skeletheld de vorm van Hero, uit dezelfde tokens', () => {
    for (const file of ['Skeleton.svelte', 'Hero.svelte']) {
      const source = readFileSync(resolve(import.meta.dirname, file), 'utf8');
      expect(source, file).toContain('aspect-ratio: var(--hero-aspect)');
      expect(source, file).toContain('height: var(--hero-h-narrow)');
      expect(source, file).toContain('border-radius: var(--radius-hero)');
      expect(source, file).toContain('margin: 4px var(--inset) 0');
      expect(source, file).not.toContain('--hero-min-h');
      expect(source, file).not.toContain('62dvh');
    }
  });
});
