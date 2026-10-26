/**
 * Scherm 21 tegen een nepserver: de tabel uit `/libraries`, `/storage/roots`
 * en `/scans`, scannen, overnemen in beheer, en de foutpaden van beide.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, library, libraryFake, root, scan } from './libraryFake';

const h = vi.hoisted(() => ({ client: null as unknown }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import LibrariesPage from './LibrariesPage.svelte';

const films = library('l1', 'Films', { item_count: 461 });
const kids = library('l2', 'Kids', { item_count: 5, managed: 'config' });
const boeken = library('l3', 'Archief', { kind: 'shows' });

function setup(fail: Parameters<typeof libraryFake>[0]['fail'] = {}) {
  const server = libraryFake({
    libraries: [films, kids, boeken],
    roots: [
      root('/media/Films', films),
      root('/media/Kids', kids),
      root('/media/Archief', boeken, { mounted: false })
    ],
    scans: { l1: scan('l1', 'done') },
    fail
  });
  h.client = server.client;
  return server;
}

function row(name: string): HTMLElement {
  return screen.getByRole('link', { name }).closest('tr') as HTMLElement;
}

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('scherm 21, bibliotheken', () => {
  it('toont elke bibliotheek met soort, opslag, inhoud en laatste scan', async () => {
    setup();
    render(LibrariesPage);
    await screen.findByRole('link', { name: 'Films' });

    const filmsRow = within(row('Films'));
    expect(filmsRow.getByText('/media/Films')).toBeInTheDocument();
    expect(filmsRow.getByText('461 titels')).toBeInTheDocument();
    expect(filmsRow.getByText(/3 nieuw/)).toBeInTheDocument();
    expect(filmsRow.getByRole('link', { name: 'Films bewerken' })).toHaveAttribute(
      'href',
      '/admin/libraries/l1'
    );
    expect(within(row('Kids')).getByText('beheerd via .env')).toBeInTheDocument();
    expect(within(row('Kids')).getByText('nog niet gescand')).toBeInTheDocument();
    expect(within(row('Archief')).getByText('niet gemount')).toBeInTheDocument();
    expect(screen.getByText('Kids komt nog uit de omgevingsvariabele.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Bibliotheek toevoegen' })).toHaveAttribute(
      'href',
      '/admin/libraries/new'
    );
  });

  it('start een scan met POST en zet de rij in de wachtrij', async () => {
    const server = setup();
    render(LibrariesPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Films scannen' }));

    await waitFor(() => expect(within(row('Films')).getByText('in de wachtrij')).toBeInTheDocument());
    expect(server.writes()).toEqual([{ method: 'POST', path: '/libraries/l1/scan', body: undefined }]);
    expect(screen.getByRole('button', { name: 'Films scannen' })).toBeDisabled();
    expect(screen.getByText('De scan van Films staat in de wachtrij.')).toBeInTheDocument();
  });

  it('wijst bij een lopende scan naar Scans en taken', async () => {
    setup({ 'POST /libraries/l1/scan': apiError('library.scan_in_progress', 409) });
    render(LibrariesPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Films scannen' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Er staat al een scan van Films in de wachtrij');
    expect(within(alert).getByRole('link', { name: 'Naar scans en taken' })).toHaveAttribute(
      'href',
      '/admin/activity'
    );
  });

  it('biedt bij een niet-gemounte root Opslag aan in plaats van scannen', async () => {
    setup();
    render(LibrariesPage);
    await screen.findByRole('link', { name: 'Films' });
    expect(within(row('Archief')).queryByRole('button', { name: 'Archief scannen' })).toBeNull();
    expect(within(row('Archief')).getByRole('link', { name: 'Opslag' })).toHaveAttribute(
      'href',
      '/admin/storage'
    );
  });

  it('neemt een .env-bibliotheek pas na bevestiging over', async () => {
    const server = setup();
    render(LibrariesPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Overnemen in beheer' }));

    const dialog = screen.getByRole('dialog', { name: 'Kids overnemen in beheer?' });
    expect(server.writes()).toEqual([]);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Overnemen' }));

    await waitFor(() => expect(server.writes()).toEqual([{ method: 'POST', path: '/libraries/l2/adopt', body: undefined }]));
    await waitFor(() => expect(within(row('Kids')).queryByText('beheerd via .env')).toBeNull());
    expect(screen.queryByText('Kids komt nog uit de omgevingsvariabele.')).toBeNull();
  });

  it('zegt bij library.not_config_managed dat er niets over te nemen is, met opnieuw laden', async () => {
    setup({ 'POST /libraries/l2/adopt': apiError('library.not_config_managed', 409) });
    render(LibrariesPage);
    await userEvent.click(await screen.findByRole('button', { name: 'Overnemen in beheer' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Overnemen' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Kids wordt al in Pleya beheerd');
    expect(within(alert).getByRole('button', { name: 'Opnieuw laden' })).toBeInTheDocument();
  });

  it('meldt een verwijdering die net gebeurd is', async () => {
    setup();
    render(LibrariesPage, { props: { removed: 'Oud' } });
    expect(await screen.findByText('Oud is verwijderd. De bestanden op schijf zijn niet aangeraakt.')).toBeInTheDocument();
  });

  it('geeft een foutstaat met opnieuw proberen als de lijst niet laadt', async () => {
    setup({ 'GET /storage/roots': apiError('server.internal', 500) });
    render(LibrariesPage);
    expect(await screen.findByRole('button', { name: 'Opnieuw proberen' })).toBeInTheDocument();
  });
});
