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
});
