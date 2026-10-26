/**
 * Scherm 24 tegen een nepserver: de tabel uit `/storage/roots`, de
 * waarschuwing bij een niet-gemounte root, en Opnieuw controleren.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, library, opsFake, root, scan } from './opsFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import StoragePage from './StoragePage.svelte';

const films = library('l1', 'Films');
const boeken = library('l2', 'Boeken', { kind: 'shows' });

const MOUNTED = [
  root('/media/Films', films, { free_bytes: 1_100_000_000_000, total_bytes: 6_000_000_000_000 }),
  root('/media/Series', library('l3', 'Series'), {
    free_bytes: 240_000_000_000,
    total_bytes: 4_000_000_000_000
  }),
  root('/mnt/usb-archief', null, { fs_type: 'fuseblk.ntfs', inode_trusted: false })
];

function setup(roots = MOUNTED, fail: Parameters<typeof opsFake>[0]['fail'] = {}) {
  const server = opsFake({
    libraries: [films, boeken],
    roots,
    scans: [scan('l3', 'running', { id: 's1' })],
    fail
  });
  h.client = server.client;
  return server;
}

function row(path: string): HTMLElement {
  return screen.getByText(path).closest('tr') as HTMLElement;
}

beforeEach(() => setLocale('nl'));
afterEach(() => {
  setLocale('en');
  vi.useRealTimers();
});

describe('scherm 24, opslag', () => {
  it('toont elke root met bestandssysteem, inode, ruimte, bibliotheek en status', async () => {
    setup();
    render(StoragePage);
    await screen.findByText('/media/Films');

    const films = within(row('/media/Films'));
    expect(films.getByText('btrfs')).toBeInTheDocument();
    expect(films.getByText('betrouwbaar')).toBeInTheDocument();
    expect(films.getByText('1,1 TB vrij van 6 TB')).toBeInTheDocument();
    expect(films.getByText('Films')).toBeInTheDocument();
    expect(films.getByText('gemount')).toBeInTheDocument();

    const usb = within(row('/mnt/usb-archief'));
    expect(usb.getByText('fuseblk.ntfs')).toBeInTheDocument();
    expect(usb.getByText('niet betrouwbaar')).toBeInTheDocument();
    expect(usb.getByText(/scanner gebruikt signatuur/)).toBeInTheDocument();
    expect(usb.getByText('niet in gebruik')).toBeInTheDocument();
    expect(usb.getByText('geen')).toBeInTheDocument();

    expect(within(row('/media/Series')).getByText('scan bezig')).toBeInTheDocument();
    expect(screen.getByText('3 roots gemount · 2,4 TB vrij')).toBeInTheDocument();
  });

  it('meldt geen waarschuwing zolang elke root gemount is, en leest alleen', async () => {
    const server = setup();
    render(StoragePage);
    await screen.findByText('/media/Films');
    expect(screen.queryByRole('alert')).toBeNull();
    expect(server.writes()).toEqual([]);
    expect(screen.getAllByRole('button', { name: 'Opnieuw controleren' })).toHaveLength(1);
  });

  it('waarschuwt bij een niet-gemounte root, noemt de bibliotheek en toont onbekend', async () => {
    setup([
      ...MOUNTED,
      root('/volume1/media/Boeken', boeken, {
        mounted: false,
        fs_type: null,
        free_bytes: 0,
        total_bytes: 0
      })
    ]);
    render(StoragePage);

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('/volume1/media/Boeken is niet gemount.');
    expect(alert).toHaveTextContent('In gebruik door Boeken.');
    expect(within(alert).getByRole('button', { name: 'Opnieuw controleren' })).toBeInTheDocument();
    // De knop staat nu in de waarschuwing en niet nog eens in het paneel.
    expect(screen.getAllByRole('button', { name: 'Opnieuw controleren' })).toHaveLength(1);

    const down = within(row('/volume1/media/Boeken'));
    expect(down.getByText('niet gemount')).toBeInTheDocument();
    expect(down.getByText('onbekend', { selector: 'p' })).toBeInTheDocument();
    expect(screen.getByText(/1 niet bereikbaar/)).toBeInTheDocument();
  });

  it('plant de meting in met één POST en meldt dat de stand zo komt', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const server = setup();
    render(StoragePage);
    await userEvent.click(await screen.findByRole('button', { name: 'Opnieuw controleren' }));

    await waitFor(() => expect(server.writes()).toEqual(['POST /storage/roots/recheck']));
    expect(await screen.findByText(/De meetronde is ingepland/)).toBeInTheDocument();

    // Na enkele seconden leest de pagina de roots nog één keer.
    const before = server.seen.filter((s) => s.path === '/storage/roots').length;
    await vi.advanceTimersByTimeAsync(3100);
    await waitFor(() =>
      expect(server.seen.filter((s) => s.path === '/storage/roots').length).toBe(before + 1)
    );
  });

  it('toont bij een falende meting de fout met uitweg en laat de tabel staan', async () => {
    const server = setup(MOUNTED, { 'POST /storage/roots/recheck': apiError('server.internal', 500) });
    render(StoragePage);
    await userEvent.click(await screen.findByRole('button', { name: 'Opnieuw controleren' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Er ging iets mis op de server');
    expect(within(alert).getByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
    expect(screen.queryByText(/De meetronde is ingepland/)).toBeNull();
    expect(screen.getByText('/media/Films')).toBeInTheDocument();
    expect(server.writes()).toEqual(['POST /storage/roots/recheck']);
  });

  it('wijst een lid zonder beheerrechten naar Pleya', async () => {
    setup(MOUNTED, { 'POST /storage/roots/recheck': apiError('auth.user_not_found', 404) });
    render(StoragePage);
    await userEvent.click(await screen.findByRole('button', { name: 'Opnieuw controleren' }));
    const alert = await screen.findByRole('alert');
    expect(within(alert).getByRole('link', { name: 'Terug naar Pleya' })).toHaveAttribute('href', '/');
  });

  it('geeft een foutstaat met opnieuw proberen als de roots niet laden', async () => {
    setup(MOUNTED, { 'GET /storage/roots': apiError('server.internal', 500) });
    render(StoragePage);
    expect(await screen.findByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
    expect(screen.queryByText('/media/Films')).toBeNull();
  });

  it('zegt dat er geen roots zijn als de lijst leeg is', async () => {
    setup([]);
    render(StoragePage);
    expect(await screen.findByText('De server meldt geen opslagroots.')).toBeInTheDocument();
  });
});
