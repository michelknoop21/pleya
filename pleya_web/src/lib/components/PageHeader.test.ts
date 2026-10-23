import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import PageHeader from './PageHeader.svelte';

const html = (markup: string) => createRawSnippet(() => ({ render: () => markup }));

describe('PageHeader', () => {
  it('rendert precies één h1 met de titel', () => {
    const { container } = render(PageHeader, { props: { title: 'Bibliotheken' } });
    expect(container.querySelectorAll('h1')).toHaveLength(1);
    expect(screen.getByRole('heading', { level: 1, name: 'Bibliotheken' })).toBeInTheDocument();
  });

  it('laat bijschrift en acties weg als ze niet gegeven zijn', () => {
    const { container } = render(PageHeader, { props: { title: 'Bibliotheken' } });
    expect(container.querySelector('.ph__sub')).toBeNull();
    expect(container.querySelector('.ph__actions')).toBeNull();
  });

  it('zet het aantal in de kop, want het hoort bij de paginanaam', () => {
    render(PageHeader, { props: { title: 'Alle films', sub: 461 } });
    const heading = screen.getByRole('heading', { level: 1 });
    expect(heading).toHaveAccessibleName('Alle films 461');
    expect(heading.querySelector('.ph__sub')).toHaveTextContent('461');
  });

  it('toont een aantal van nul gewoon, en een lege tekst niet', () => {
    const { container, unmount } = render(PageHeader, { props: { title: 'Films', sub: 0 } });
    expect(container.querySelector('.ph__sub')).toHaveTextContent('0');
    unmount();

    const empty = render(PageHeader, { props: { title: 'Films', sub: '' } });
    expect(empty.container.querySelector('.ph__sub')).toBeNull();
  });

  it('zet de acties naast de kop en niet erin', () => {
    render(PageHeader, {
      props: {
        title: 'Verzamelingen',
        actions: html('<a class="btn btn--sm" href="/new">Nieuwe verzameling</a>')
      }
    });
    const heading = screen.getByRole('heading', { level: 1 });
    const link = screen.getByRole('link', { name: 'Nieuwe verzameling' });
    expect(heading).toHaveAccessibleName('Verzamelingen');
    expect(heading).not.toContainElement(link);
    expect(link.parentElement).toHaveClass('ph__actions');
  });
});
