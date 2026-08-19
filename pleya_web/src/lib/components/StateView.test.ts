import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import StateView from './StateView.svelte';

describe('StateView', () => {
  it('gebruikt de gedeelde tekst uit de i18n-bron van de app als er geen titel is', () => {
    render(StateView, { props: { kind: 'empty' } });
    expect(screen.getByText('Nothing here yet')).toBeInTheDocument();
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
