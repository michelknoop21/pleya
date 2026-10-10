import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import SkeletonPage from './SkeletonPage.svelte';

describe('SkeletonPage', () => {
  it('meldt het laden aan een schermlezer met de gedeelde laadtekst', () => {
    render(SkeletonPage);
    const status = screen.getByRole('status');
    expect(status).toHaveTextContent('Loading…');
    expect(status).toHaveClass('visually-hidden');
    // De statusregel staat buiten de bezige container: een aria-busy-voorouder
    // zou de aankondiging inhouden.
    expect(status.closest('[aria-busy="true"]')).toBeNull();
    const busy = status.parentElement?.querySelector('.skp__body');
    expect(busy).toHaveAttribute('aria-busy', 'true');
  });

  it('houdt de blokken buiten de toegankelijkheidsboom', () => {
    const { container } = render(SkeletonPage);
    expect(container.querySelector('.skp__body')).toHaveAttribute('aria-hidden', 'true');
  });

  it('tekent op de startpagina een hero en twee rails met kaarten', () => {
    const { container } = render(SkeletonPage, { props: { variant: 'home' } });
    expect(container.querySelectorAll('.skel--hero')).toHaveLength(1);
    const rails = container.querySelectorAll('.skp__rail');
    expect(rails).toHaveLength(2);
    for (const rail of rails) {
      expect(rail.querySelectorAll('.skel--title')).toHaveLength(1);
      expect(rail.querySelectorAll('.skp__cell .skc').length).toBeGreaterThan(0);
    }
  });

  it('tekent voor een bibliotheek alleen het raster, zonder hero', () => {
    const { container } = render(SkeletonPage, { props: { variant: 'grid' } });
    expect(container.querySelector('.skel--hero')).toBeNull();
    expect(container.querySelectorAll('.skp__grid .skc').length).toBeGreaterThan(0);
  });

  it('tekent voor een item een poster naast titel en regels', () => {
    const { container } = render(SkeletonPage, { props: { variant: 'detail' } });
    expect(container.querySelector('.skp__poster .skel--block')).not.toBeNull();
    expect(container.querySelectorAll('.skp__lines .skel--line').length).toBeGreaterThan(0);
  });

  it('houdt het voor de schil klein, omdat nog niet vaststaat wat er komt', () => {
    const { container } = render(SkeletonPage, { props: { variant: 'compact' } });
    expect(container.querySelector('.skp__compact')).not.toBeNull();
    expect(container.querySelector('.skc')).toBeNull();
    expect(container.querySelector('.skel--hero')).toBeNull();
  });

  it('neemt een eigen label over', () => {
    render(SkeletonPage, { props: { label: 'Bibliotheek laden' } });
    expect(screen.getByRole('status')).toHaveTextContent('Bibliotheek laden');
  });
});
