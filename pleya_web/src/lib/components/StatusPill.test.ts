import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import StatusPill from './StatusPill.svelte';

describe('StatusPill', () => {
  it.each(['ok', 'warn', 'err', 'run', 'idle'] as const)('draagt de toon %s als klasse', (tone) => {
    render(StatusPill, { props: { label: 'state', tone } });
    expect(screen.getByText('state')).toHaveClass('pill', `pill--${tone}`);
  });

  it('is standaard idle met een stip die een schermlezer niet ziet', () => {
    const { container } = render(StatusPill, { props: { label: 'revoked' } });
    const pill = screen.getByText('revoked');
    expect(pill).toHaveClass('pill--idle');
    expect(pill).toHaveTextContent(/^revoked$/);
    expect(container.querySelector('.pill__dot')).toHaveAttribute('aria-hidden', 'true');
  });

  it('laat de stip weg op verzoek en vervangt hem door een icoon', () => {
    const { container, unmount } = render(StatusPill, {
      props: { label: 'skipped', tone: 'warn', dot: false }
    });
    expect(container.querySelector('.pill__dot')).toBeNull();
    unmount();

    const icon = createRawSnippet(() => ({ render: () => '<svg data-testid="check"></svg>' }));
    const r = render(StatusPill, { props: { label: 'done', tone: 'ok', icon } });
    expect(r.container.querySelector('.pill__dot')).toBeNull();
    expect(screen.getByTestId('check')).toBeInTheDocument();
  });

  it('heeft een kleine maat voor tabelcellen', () => {
    render(StatusPill, { props: { label: 'not mounted', tone: 'err', size: 'sm' } });
    expect(screen.getByText('not mounted')).toHaveClass('pill--sm');
  });
});
