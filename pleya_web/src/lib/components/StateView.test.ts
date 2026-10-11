import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { createRawSnippet } from 'svelte';

import StateView from './StateView.svelte';

describe('StateView', () => {
  it('gebruikt de gedeelde tekst uit de i18n-bron van de app als er geen titel is', () => {
    render(StateView, { props: { kind: 'empty' } });
    expect(screen.getByText('Nothing here yet')).toBeInTheDocument();
  });

  it('kent alleen leeg en fout; laden is een skelet en geen spinner meer', () => {
    const { container } = render(StateView);
    expect(screen.getByText('Nothing here yet')).toBeInTheDocument();
    expect(container.querySelector('.state__icon')).not.toBeNull();
    expect(container.querySelector('.state__spinner')).toBeNull();
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('meldt een fout als alert, zodat een schermlezer hem meteen hoort', () => {
    render(StateView, { props: { kind: 'error', message: 'De server antwoordde niet.' } });
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('Something went wrong');
    expect(alert).toHaveTextContent('De server antwoordde niet.');
  });

  it('toont een herhaalknop alleen wanneer er iets te herhalen valt', () => {
    const { unmount } = render(StateView, { props: { kind: 'error' } });
    expect(screen.queryByRole('button')).toBeNull();
    unmount();

    render(StateView, { props: { kind: 'error', onRetry: () => {} } });
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument();
  });

  it('is met het toetsenbord te bedienen', async () => {
    const onRetry = vi.fn();
    render(StateView, { props: { kind: 'error', onRetry } });

    const user = userEvent.setup();
    await user.tab();
    expect(screen.getByRole('button', { name: 'Retry' })).toHaveFocus();
    await user.keyboard('{Enter}');
    expect(onRetry).toHaveBeenCalledTimes(1);
  });
});

describe('StateView in de vorm van 13', () => {
  const html = (markup: string) => createRawSnippet(() => ({ render: () => markup }));

  it('zet de titel als h2 onder de paginakop, en binnen een sectie als alinea', () => {
    const { unmount } = render(StateView, { props: { title: 'Nog geen boeken' } });
    expect(screen.getByRole('heading', { level: 2, name: 'Nog geen boeken' })).toBeInTheDocument();
    unmount();

    render(StateView, { props: { title: 'Geen afleveringen', compact: true } });
    expect(screen.queryByRole('heading')).toBeNull();
    expect(screen.getByText('Geen afleveringen')).toBeInTheDocument();
  });

  it('toont de meegegeven acties in de knoppenrij, naast de herhaalknop', () => {
    render(StateView, {
      props: {
        kind: 'error',
        onRetry: () => {},
        actions: html('<a class="btn btn--ghost btn--sm" href="/server">Serverbeheer</a>')
      }
    });
    const retry = screen.getByRole('button', { name: 'Retry' });
    const link = screen.getByRole('link', { name: 'Serverbeheer' });
    expect(retry.parentElement).toBe(link.parentElement);
    expect(retry.parentElement).toHaveClass('state__actions');
    // De herhaalknop is de primaire uitweg: de gewone capsule, klein.
    expect(retry).toHaveClass('btn', 'btn--sm');
    expect(retry).not.toHaveClass('btn--secondary');
  });

  it('laat de knoppenrij weg als er geen uitweg is', () => {
    const { container } = render(StateView, { props: { title: 'Leeg' } });
    expect(container.querySelector('.state__actions')).toBeNull();
  });

  it('gebruikt het meegegeven icoon in plaats van het standaardpad', () => {
    const { container, unmount } = render(StateView, {
      props: { icon: html('<svg data-testid="boek" viewBox="0 0 24 24"></svg>') }
    });
    const slot = container.querySelector('.state__icon');
    expect(slot).toHaveAttribute('aria-hidden', 'true');
    expect(slot?.querySelector('[data-testid="boek"]')).not.toBeNull();
    expect(slot?.querySelectorAll('svg')).toHaveLength(1);
    unmount();

    const fallback = render(StateView).container.querySelector('.state__icon svg path');
    expect(fallback).not.toBeNull();
  });

  it('is alleen bij een fout een alert, een lege staat onderbreekt niemand', () => {
    const { unmount } = render(StateView, { props: { kind: 'empty', title: 'Leeg' } });
    expect(screen.queryByRole('alert')).toBeNull();
    unmount();

    render(StateView, { props: { kind: 'error' } });
    expect(screen.getByRole('alert')).toBeInTheDocument();
  });
});
