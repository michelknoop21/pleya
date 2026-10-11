import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen } from '@testing-library/svelte';

import UnreachableState from './UnreachableState.svelte';
import { setLocale } from '../i18n';

type Props = {
  name?: string;
  host?: string;
  lastContactAt?: string | null;
  signedIn?: boolean;
  onRetry?: () => Promise<void>;
};

function setup(props: Props = {}) {
  const onRetry = props.onRetry ?? vi.fn(async () => undefined);
  const view = render(UnreachableState, {
    props: {
      name: 'Pleya-server',
      host: 'web.pleya.app',
      lastContactAt: null,
      signedIn: false,
      ...props,
      onRetry
    }
  });
  return { ...view, onRetry };
}

/** Laat de klok `seconds` lopen en wacht de belofte van een poging af. */
async function tick(seconds: number): Promise<void> {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(seconds * 1000);
  });
}

beforeEach(() => {
  vi.useFakeTimers();
  setLocale('en');
});

afterEach(() => {
  vi.useRealTimers();
  setLocale('en');
});

describe('de aftelling', () => {
  it('probeert na 2, 4, 8, 16 en daarna elke 30 s', async () => {
    const { onRetry } = setup();
    const expected = [2, 4, 8, 16, 30, 30];
    let total = 0;
    for (const [index, seconds] of expected.entries()) {
      await tick(seconds - 1);
      expect(onRetry, `nog geen poging ${index + 1} na ${seconds - 1} s`).toHaveBeenCalledTimes(index);
      await tick(1);
      total += 1;
      expect(onRetry, `poging ${index + 1} na ${seconds} s`).toHaveBeenCalledTimes(total);
    }
  });

  it('toont het getal zonder live-regio en meldt alleen het verbinden', async () => {
    let finish: () => void = () => undefined;
    const onRetry = vi.fn(() => new Promise<void>((resolve) => (finish = resolve)));
    setup({ onRetry });

    const countdown = screen.getByText('retrying in 2 s');
    expect(countdown.closest('[role="status"], [role="alert"], [aria-live]')).toBeNull();
    expect(screen.getByRole('status')).toHaveTextContent('');

    await tick(2);
    expect(screen.getByRole('status')).toHaveTextContent('Connecting…');
    await act(async () => finish());
    expect(screen.getByRole('status')).toHaveTextContent('');
    expect(screen.getByText('retrying in 4 s')).toBeInTheDocument();
  });

  it('de knop stopt de timer, probeert meteen en zet de reeks terug op 2', async () => {
    const { onRetry } = setup();
    // Drie automatische pogingen: de volgende zou na 16 s komen.
    await tick(2 + 4 + 8);
    expect(onRetry).toHaveBeenCalledTimes(3);
    expect(screen.getByText('retrying in 16 s')).toBeInTheDocument();

    await act(async () => screen.getByRole('button', { name: 'Retry now' }).click());
    expect(onRetry).toHaveBeenCalledTimes(4);
    expect(screen.getByText('retrying in 2 s')).toBeInTheDocument();

    // De oude timer is weg: na 2 s precies één poging erbij, niet twee.
    await tick(2);
    expect(onRetry).toHaveBeenCalledTimes(5);
  });

  it('laat bij ontkoppelen geen timer achter', async () => {
    const { unmount, onRetry } = setup();
    expect(vi.getTimerCount()).toBe(1);
    unmount();
    expect(vi.getTimerCount()).toBe(0);
    await tick(60);
    expect(onRetry).not.toHaveBeenCalled();
  });

  it('start geen nieuwe timer als de poging slaagde en de staat al weg is', async () => {
    let finish: () => void = () => undefined;
    const onRetry = vi.fn(() => new Promise<void>((resolve) => (finish = resolve)));
    const { unmount } = setup({ onRetry });
    await tick(2);
    unmount();
    await act(async () => finish());
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('de inhoud', () => {
  it('noemt de server bij naam als kop van de pagina, met de host in mono', () => {
    setup();
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      'Pleya-server is not reachable'
    );
    const host = screen.getByText('web.pleya.app');
    expect(host).toHaveClass('unreachable__host');
    expect(host.parentElement).toHaveTextContent('The address web.pleya.app is not responding.');
  });

  it('valt zonder record terug op de host, zonder laatste contact', () => {
    setup({ name: 'nas.local:8832', host: 'nas.local:8832' });
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      'nas.local:8832 is not reachable'
    );
    expect(screen.queryByText(/Last contact/)).toBeNull();
  });

  it('toont het laatste contact relatief, in de actieve taal', () => {
    vi.setSystemTime(new Date('2026-10-11T12:03:00Z'));
    setLocale('nl');
    setup({ lastContactAt: '2026-10-11T12:00:00Z' });
    expect(screen.getByText('Laatste contact 3 minuten geleden')).toBeInTheDocument();
    expect(screen.getByText('opnieuw proberen over 2 s')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Nu opnieuw proberen' })).toBeInTheDocument();
  });

  it('zegt alleen dat je ingelogd bent als er een refreshtoken is', () => {
    const { unmount } = setup({ signedIn: false });
    expect(screen.queryByText(/still signed in/)).toBeNull();
    unmount();
    setup({ signedIn: true });
    expect(screen.getByText(/still signed in/)).toBeInTheDocument();
  });

  it('is geen alert, anders leest een schermlezer de aftelling voor', () => {
    setup();
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
