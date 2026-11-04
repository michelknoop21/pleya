/**
 * Oude toestellen opruimen op scherm 27 tegen een nepserver (DEC-164). De
 * regels die schade voorkomen staan voorop: niets zonder bevestiging, nooit het
 * eigen toestel of een API-token, en een fout halverwege stopt de rij niet en
 * zegt wat er overbleef.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, library, user, userFake, userSession } from './userFake';

const h = vi.hoisted(() => ({
  client: null as unknown,
  meId: 'u1',
  goto: vi.fn(async () => {}),
  load: vi.fn(async () => {})
}));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    },
    get me() {
      return { id: h.meId };
    },
    load: h.load
  }
}));

import UserEditor from './UserEditor.svelte';

const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();

function setup(fail: Parameters<typeof userFake>[0]['fail'] = {}) {
  const server = userFake({
    users: [user('u1', 'Michel', 'owner')],
    libraries: [library('l1', 'Films')],
    sessions: {
      u1: [
        userSession('mine', 'Deze browser', { current: true, last_seen_at: daysAgo(120) }),
        userSession('tv', 'Apple TV woonkamer', { last_seen_at: daysAgo(1) }),
        userSession('agent', 'Mijn agent', { kind: 'api', last_seen_at: daysAgo(200) }),
        userSession('old1', 'Unknown device', { last_seen_at: daysAgo(52), created_at: '2026-09-04T10:00:00Z' }),
        userSession('old2', 'Firefox op Windows', { last_seen_at: daysAgo(35) }),
        userSession('old3', 'Unknown device', { last_seen_at: daysAgo(95) })
      ]
    },
    fail
  });
  h.client = server.client;
  return server;
}

async function openCleanup() {
  render(UserEditor, { props: { id: 'u1' } });
  await screen.findByRole('heading', { level: 1 });
  await userEvent.click(screen.getByRole('button', { name: 'Oude toestellen opruimen' }));
  return screen.findByRole('dialog');
}

beforeEach(() => {
  setLocale('nl');
  h.meId = 'u1';
});
afterEach(() => setLocale('en'));

describe('oude toestellen opruimen, scherm 27', () => {
  it('toont een toestel zonder naam als Onbekend toestel', async () => {
    setup();
    render(UserEditor, { props: { id: 'u1' } });
    await screen.findByRole('heading', { level: 1 });
    expect(screen.getAllByText('Onbekend toestel')).toHaveLength(2);
    expect(screen.queryByText('Unknown device')).not.toBeInTheDocument();
  });

  it('noemt aantal en toestellen, en sluit het eigen toestel, recente toestellen en API-tokens uit', async () => {
    const server = setup();
    const dialog = await openCleanup();
    expect(within(dialog).getByText('3 toestellen worden uitgelogd:')).toBeInTheDocument();
    const listed = within(dialog).getAllByRole('listitem').map((li) => li.textContent ?? '');
    expect(listed).toHaveLength(3);
    expect(listed.join('\n')).toContain('Onbekend toestel, aangemeld op 4 september 2026');
    expect(listed.join('\n')).toContain('Firefox op Windows');
    for (const name of ['Deze browser', 'Apple TV woonkamer', 'Mijn agent']) {
      expect(listed.join('\n')).not.toContain(name);
    }
    // Openen schrijft niets: zonder bevestiging gaat er geen enkele intrekking uit.
    expect(server.writes()).toEqual([]);
  });

  it('stuurt niets bij annuleren (negatieve controle)', async () => {
    const server = setup();
    const dialog = await openCleanup();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(server.writes()).toEqual([]);
  });

  it('volgt de gekozen periode', async () => {
    setup();
    const dialog = await openCleanup();
    const period = within(dialog).getByLabelText('Niet gezien in meer dan');
    expect(within(period).getAllByRole('option').map((o) => o.textContent)).toEqual(['30 dagen', '60 dagen', '90 dagen']);
    expect(period).toHaveValue('30');
    await userEvent.selectOptions(period, '90');
    expect(within(dialog).getByText('1 toestel wordt uitgelogd:')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: '1 toestel uitloggen' })).toBeEnabled();
  });

  it('trekt na bevestiging precies de oude toestellen in, één voor één, en ververst de lijst', async () => {
    const server = setup();
    const dialog = await openCleanup();
    await userEvent.click(within(dialog).getByRole('button', { name: '3 toestellen uitloggen' }));
    await waitFor(() =>
      expect(server.writes().map((w) => `${w.method} ${w.path}`)).toEqual([
        'DELETE /sessions/old1',
        'DELETE /sessions/old2',
        'DELETE /sessions/old3'
      ])
    );
    expect(await screen.findByText('3 oude toestellen uitgelogd.')).toBeInTheDocument();
    expect(screen.queryByText('Firefox op Windows')).not.toBeInTheDocument();
    expect(screen.getByText('Apple TV woonkamer')).toBeInTheDocument();
    expect(screen.getByText('Mijn agent')).toBeInTheDocument();
  });

  it('gaat door na een fout en zegt hoeveel er lukte, met een uitweg', async () => {
    const server = setup({ 'DELETE /sessions/old2': apiError('server.internal', 500) });
    const dialog = await openCleanup();
    await userEvent.click(within(dialog).getByRole('button', { name: '3 toestellen uitloggen' }));
    await waitFor(() => expect(server.writes()).toHaveLength(3));
    const alert = await screen.findByText(/2 van 3 toestellen uitgelogd/);
    expect(alert).toHaveTextContent('Bij 1 lukte het niet');
    // De lijst is ververst: alleen het mislukte oude toestel staat er nog.
    expect(screen.getByText('Firefox op Windows')).toBeInTheDocument();
    expect(screen.queryByText('Onbekend toestel')).not.toBeInTheDocument();
    // Opnieuw proberen opent de dialoog voor wat er over is.
    await userEvent.click(screen.getByRole('button', { name: 'Opnieuw proberen' }));
    expect(within(await screen.findByRole('dialog')).getByText('1 toestel wordt uitgelogd:')).toBeInTheDocument();
  });
});
