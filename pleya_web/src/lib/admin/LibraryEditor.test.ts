/**
 * Scherm 22 en 23 tegen een nepserver: bewerken met alleen de gewijzigde
 * velden, toevoegen, een .env-bibliotheek die alleen te lezen is, verwijderen
 * achter de getypte naam, en de foutpaden van bewerken en verwijderen.
 */
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { apiError, library, libraryFake, root, scan } from './libraryFake';

const h = vi.hoisted(() => ({ client: null as unknown, goto: vi.fn(async () => {}) }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import LibraryEditor from './LibraryEditor.svelte';

const films = library('l1', 'Films', { item_count: 461, scan_interval_seconds: 21600 });
const leeg = library('l2', 'Leeg');
const kids = library('l3', 'Kids', { managed: 'config', item_count: 5 });

function setup(fail: Parameters<typeof libraryFake>[0]['fail'] = {}) {
  const server = libraryFake({
    libraries: [films, leeg, kids],
    roots: [
      root('/media/Films', films),
      root('/media/Leeg', leeg),
      root('/media/Kids', kids),
      root('/media/vrij', null),
      root('/media/ntfs', null, { fs_type: 'fuseblk.ntfs', inode_trusted: false })
    ],
    scans: { l1: scan('l1', 'done') },
    fail
  });
  h.client = server.client;
  return server;
}

beforeEach(() => {
  setLocale('nl');
  h.goto.mockClear();
});
afterEach(() => setLocale('en'));

async function openEditor(id: string | null) {
  render(LibraryEditor, { props: { id } });
  return screen.findByRole('textbox', { name: 'Naam' });
}

describe('scherm 22, bewerken', () => {
  it('toont instellingen, roots en stand van de bibliotheek', async () => {
    setup();
    const name = await openEditor('l1');
    expect(name).toHaveValue('Films');
    expect(screen.getByRole('heading', { level: 1, name: 'Films' })).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: /\/media\/Films/ })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: /\/media\/Leeg/ })).toBeDisabled();
    expect(screen.getByText('in gebruik door Leeg')).toBeInTheDocument();
    // Gevuld: alleen de huidige soort is te kiezen.
    expect(screen.getByRole('radio', { name: 'Series' })).toBeDisabled();
    expect(screen.getByRole('combobox', { name: 'Scannen' })).toHaveValue('21600');
    expect(screen.getByText('461 titels')).toBeInTheDocument();
    expect(await screen.findByText('bij 90% van de titels')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Opslaan' })).toBeDisabled();
  });

  it('noemt een root zonder betrouwbare inodes bij wat dat betekent, niet bij het bestandssysteem', async () => {
    setup();
    await openEditor('l1');
    // De uitleg staat al onder het pad; de pil zegt het in twee woorden.
    expect(screen.getByText('inode onbetrouwbaar')).toBeInTheDocument();
    expect(screen.queryByText('ntfs')).not.toBeInTheDocument();
  });

  it('stuurt bij opslaan alleen de gewijzigde velden met PATCH', async () => {
    const server = setup();
    const name = await openEditor('l1');
    await userEvent.clear(name);
    await userEvent.type(name, 'Films HD');
    await userEvent.click(screen.getByRole('checkbox', { name: /\/media\/vrij/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));

    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'PATCH',
          path: '/libraries/l1',
          body: { title: 'Films HD', root_paths: ['/media/Films', '/media/vrij'] }
        }
      ])
    );
    expect(await screen.findByText('Films HD is opgeslagen.')).toBeInTheDocument();
  });

  it('legt bij library.not_empty uit dat de soort vastligt', async () => {
    setup({ 'PATCH /libraries/l2': apiError('library.not_empty', 409) });
    await openEditor('l2');
    await userEvent.click(screen.getByRole('radio', { name: 'Series' }));
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'De soort van Leeg kan niet meer wisselen'
    );
  });

  it('wijst bij storage.root_not_offered naar Opslag', async () => {
    setup({ 'PATCH /libraries/l1': apiError('storage.root_not_offered', 400) });
    await openEditor('l1');
    await userEvent.click(screen.getByRole('checkbox', { name: /\/media\/vrij/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('De server weigerde een opslagroot');
    expect(within(alert).getByRole('link', { name: 'Bekijk opslag' })).toHaveAttribute(
      'href',
      '/admin/storage'
    );
  });

  it('biedt bij library.config_managed overnemen aan', async () => {
    setup({ 'PATCH /libraries/l1': apiError('library.config_managed', 409) });
    const name = await openEditor('l1');
    await userEvent.type(name, ' 2');
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('komt uit PLEYA_SERVER_LIBRARIES');
    expect(within(alert).getByRole('button', { name: 'Overnemen in beheer' })).toBeInTheDocument();
  });

  it('noemt het verzoeknummer bij server.internal en laat opnieuw proberen', async () => {
    const server = setup({
      'PATCH /libraries/l1': apiError('server.internal', 500, { request_id: 'req-7' })
    });
    const name = await openEditor('l1');
    await userEvent.type(name, ' 2');
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('req-7');
    await userEvent.click(within(alert).getByRole('button', { name: 'Opnieuw proberen' }));
    await waitFor(() => expect(server.writes()).toHaveLength(2));
  });

  it('toont een .env-bibliotheek alleen-lezen, zonder opslaan of verwijderen', async () => {
    const server = setup();
    const name = await openEditor('l3');
    expect(name).toBeDisabled();
    expect(screen.queryByRole('button', { name: 'Opslaan' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Bibliotheek verwijderen' })).toBeNull();
    expect(screen.getByText('Kids komt nog uit de omgevingsvariabele.')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Overnemen in beheer' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Overnemen' }));
    await waitFor(() => expect(screen.getByRole('textbox', { name: 'Naam' })).toBeEnabled());
    expect(server.writes()).toEqual([{ method: 'POST', path: '/libraries/l3/adopt', body: undefined }]);
  });

  it('meldt een onbekend id met een weg terug', async () => {
    setup();
    render(LibraryEditor, { props: { id: 'weg' } });
    expect(await screen.findByText('Bibliotheek niet gevonden')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Terug naar bibliotheken' })).toHaveAttribute(
      'href',
      '/admin/libraries'
    );
  });
});

describe('scherm 22, toevoegen', () => {
  it('maakt een bibliotheek aan met POST en gaat terug naar de lijst', async () => {
    const server = setup();
    const name = await openEditor(null);
    expect(screen.getByRole('button', { name: 'Toevoegen' })).toBeDisabled();
    await userEvent.type(name, 'Docu');
    await userEvent.click(screen.getByRole('checkbox', { name: /\/media\/vrij/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));

    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'POST',
          path: '/libraries',
          body: { title: 'Docu', kind: 'movies', root_paths: ['/media/vrij'], scan_on_start: true }
        }
      ])
    );
    expect(h.goto).toHaveBeenCalledWith('/admin/libraries?added=Docu');
  });

  it('vraagt bij library.slug_taken om een andere naam', async () => {
    setup({ 'POST /libraries': apiError('library.slug_taken', 409) });
    const name = await openEditor(null);
    await userEvent.type(name, 'Films');
    await userEvent.click(screen.getByRole('checkbox', { name: /\/media\/vrij/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Kies een andere naam');
    expect(h.goto).not.toHaveBeenCalled();
  });
});

describe('scherm 23, verwijderen', () => {
  async function openDialog() {
    await openEditor('l1');
    await userEvent.click(screen.getByRole('button', { name: 'Bibliotheek verwijderen' }));
    return screen.getByRole('dialog', { name: 'Bibliotheek Films verwijderen?' });
  }

  it('stuurt zonder de exacte naam geen DELETE (negatieve controle)', async () => {
    const server = setup();
    const dialog = await openDialog();
    const field = within(dialog).getByRole('textbox');
    const confirm = within(dialog).getByRole('button', { name: 'Verwijderen' });

    await userEvent.type(field, 'films');
    expect(confirm).toBeDisabled();
    // Ook Enter in het veld verstuurt niets zolang de naam niet klopt.
    await userEvent.type(field, '{Enter}');
    await userEvent.click(confirm);
    expect(server.writes()).toEqual([]);
  });

  it('verwijdert met de titel als bevestiging en gaat terug naar de lijst', async () => {
    const server = setup();
    const dialog = await openDialog();
    expect(dialog).toHaveTextContent('Dit verwijdert 461 titels uit de catalogus');
    await userEvent.type(within(dialog).getByRole('textbox'), 'Films');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Verwijderen' }));

    await waitFor(() =>
      expect(server.writes()).toEqual([
        { method: 'DELETE', path: '/libraries/l1', body: { confirm: 'Films' } }
      ])
    );
    expect(h.goto).toHaveBeenCalledWith('/admin/libraries?removed=Films');
  });

  it('legt library.confirm_mismatch uit en laat opnieuw laden', async () => {
    setup({ 'DELETE /libraries/l1': apiError('library.confirm_mismatch', 409) });
    const dialog = await openDialog();
    await userEvent.type(within(dialog).getByRole('textbox'), 'Films');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Verwijderen' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('De naam kwam niet overeen met de titel op de server');
    expect(within(alert).getByRole('button', { name: 'Opnieuw laden' })).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(h.goto).not.toHaveBeenCalled();
  });

  it('legt library.config_managed bij verwijderen uit', async () => {
    setup({ 'DELETE /libraries/l1': apiError('library.config_managed', 409) });
    const dialog = await openDialog();
    await userEvent.type(within(dialog).getByRole('textbox'), 'Films');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Verwijderen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Films komt uit PLEYA_SERVER_LIBRARIES');
  });

  it('wijst bij library.not_found terug naar de lijst', async () => {
    setup({ 'DELETE /libraries/l1': apiError('library.not_found', 404) });
    const dialog = await openDialog();
    await userEvent.type(within(dialog).getByRole('textbox'), 'Films');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Verwijderen' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Films staat niet meer op de server');
    expect(within(alert).getByRole('link', { name: 'Terug naar bibliotheken' })).toBeInTheDocument();
  });
});

describe('nieuwe submap onder een aangeboden mount', () => {
  const field = () => screen.getByRole('textbox', { name: 'Nieuwe map' });
  const addButton = () => screen.getByRole('button', { name: 'Map toevoegen' });

  async function addFolder(path: string) {
    await userEvent.type(field(), path);
    await userEvent.click(addButton());
  }

  it('voegt een map toe, toont hem aangevinkt en stuurt hem mee bij POST', async () => {
    const server = setup();
    const name = await openEditor(null);
    await userEvent.type(name, 'Docu');
    await addFolder('/media/Documentaires');

    expect(screen.getByRole('checkbox', { name: /\/media\/Documentaires/ })).toBeChecked();
    expect(screen.getByText('nieuwe map, nog niet opgeslagen')).toBeInTheDocument();
    expect(field()).toHaveValue('');
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));

    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'POST',
          path: '/libraries',
          body: {
            title: 'Docu',
            kind: 'movies',
            root_paths: ['/media/Documentaires'],
            scan_on_start: true
          }
        }
      ])
    );
  });

  it('voegt met Enter toe zonder het formulier te versturen', async () => {
    const server = setup();
    await openEditor(null);
    await userEvent.type(field(), '/media/Docu{Enter}');
    expect(screen.getByRole('checkbox', { name: /\/media\/Docu/ })).toBeChecked();
    expect(server.writes()).toEqual([]);
  });

  it('stuurt bij bewerken de toegevoegde map mee met PATCH', async () => {
    const server = setup();
    await openEditor('l1');
    await addFolder('/media/Nieuw');
    await userEvent.click(screen.getByRole('button', { name: 'Opslaan' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'PATCH',
          path: '/libraries/l1',
          body: { root_paths: ['/media/Films', '/media/Nieuw'] }
        }
      ])
    );
  });

  it('verwijdert een toegevoegde map weer vóór opslaan', async () => {
    const server = setup();
    const name = await openEditor(null);
    await userEvent.type(name, 'Docu');
    await addFolder('/media/Weg');
    await userEvent.click(screen.getByRole('button', { name: 'Verwijder /media/Weg' }));
    expect(screen.queryByRole('checkbox', { name: /\/media\/Weg/ })).toBeNull();
    expect(screen.getByRole('button', { name: 'Toevoegen' })).toBeDisabled();
    expect(server.writes()).toEqual([]);
  });

  it.each([
    ['relatief/pad', 'Een pad begint met een /'],
    ['/a/', 'Haal de / aan het eind'],
    ['/a/../b', 'geen . of .. bevatten'],
    ['/a//b', 'geen // bevatten'],
    ['', 'Typ eerst een pad']
  ])('keurt %j af zonder het toe te voegen', async (path, sentence) => {
    const server = setup();
    await openEditor(null);
    if (path) await userEvent.type(field(), path);
    await userEvent.click(addButton());
    expect(await screen.findByText(new RegExp(sentence))).toBeInTheDocument();
    expect(screen.queryByText('nieuwe map, nog niet opgeslagen')).toBeNull();
    expect(server.writes()).toEqual([]);
  });

  it('keurt een dubbel pad af, ook als het een server-root is', async () => {
    setup();
    await openEditor(null);
    await userEvent.click(screen.getByRole('checkbox', { name: /\/media\/vrij/ }));
    await addFolder('/media/vrij');
    expect(await screen.findByText('Deze map is al gekozen.')).toBeInTheDocument();
    await userEvent.clear(field());
    await addFolder('/media/Nieuw');
    await addFolder('/media/Nieuw');
    expect(screen.getAllByText('Deze map is al gekozen.')).toHaveLength(1);
    expect(screen.getAllByRole('checkbox', { name: /\/media\/Nieuw/ })).toHaveLength(1);
  });

  it('toont het invoerveld ook als alle roots bezet zijn', async () => {
    h.client = libraryFake({
      libraries: [films],
      roots: [root('/media/library/Films', films), root('/media/library/Series', films)]
    }).client;
    await openEditor(null);
    expect(screen.getByText(/Er is geen vrije opslagroot/)).toBeInTheDocument();
    expect(field()).toBeEnabled();
    expect(screen.getByText(/Bijvoorbeeld \/media\/library\/…/)).toBeInTheDocument();
  });

  describe('weigering van de server per reden', () => {
    async function submitWith(details: Record<string, unknown> | undefined) {
      setup({ 'POST /libraries': apiError('storage.root_not_offered', 400, details) });
      const name = await openEditor(null);
      await userEvent.type(name, 'Docu');
      await addFolder('/media/Documentaires');
      await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));
      return screen.findByRole('alert');
    }

    it.each([
      [
        'invalid_path',
        { reason: 'invalid_path', root: 'x' },
        'De server accepteert dit pad niet: x'
      ],
      [
        'outside_mounts',
        { reason: 'outside_mounts', root: '/data/x', mounts: ['/media/library', '/media/library2'] },
        '/data/x valt buiten de opslag die de server aanbiedt (/media/library, /media/library2)'
      ],
      [
        'overlaps_library',
        { reason: 'overlaps_library', root: '/media/library', with: '/media/library/Films', library: 'Films' },
        'Deze map valt samen met een root van Films'
      ],
      [
        'overlaps_request',
        { reason: 'overlaps_request', root: '/a', with: '/a/b' },
        '/a en /a/b overlappen elkaar'
      ],
      ['no_roots', { reason: 'no_roots' }, 'Kies minstens één opslagroot'],
      [
        'invalid_field',
        { reason: 'invalid_field', field: 'scan_interval_seconds' },
        'De server vindt het scaninterval van Docu onbruikbaar'
      ]
    ])('zegt bij %s de juiste zin', async (_reason, details, sentence) => {
      const alert = await submitWith(details);
      expect(alert).toHaveTextContent(sentence);
      expect(alert).not.toHaveTextContent('De server weigerde een opslagroot');
    });

    it('valt bij een onbekende reden terug op de generieke tekst', async () => {
      const alert = await submitWith({ reason: 'iets_nieuws' });
      expect(alert).toHaveTextContent('De server weigerde een opslagroot of een veld van Docu');
    });

    it('valt zonder details terug op de generieke tekst', async () => {
      const alert = await submitWith(undefined);
      expect(alert).toHaveTextContent('De server weigerde een opslagroot of een veld van Docu');
    });
  });
});
