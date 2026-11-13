/**
 * Scherm 27 (kop, tabs Profiel, Toegang en Toestellen) tegen een nepserver. De nadruk ligt op de regels die schade
 * voorkomen: rechten afnemen en de rechtenlijst vervangen gaan nooit zonder
 * bevestiging, een serverweigering laat het scherm intact en toont de zin,
 * de eigenaar is niet aan te raken, en wachtwoorden gaan alleen in de body.
 */
import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
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

function setup(fail: Parameters<typeof userFake>[0]['fail'] = {}) {
  const server = userFake({
    users: [
      user('u1', 'Michel', 'owner'),
      user('u2', 'Sanne', 'member'),
      user('u3', 'Kids', 'restricted'),
      user('u4', 'Beheerder2', 'admin'),
      user('u5', 'Ikzelf', 'admin')
    ],
    libraries: [library('l1', 'Films'), library('l2', 'Series')],
    sessions: {
      u1: [userSession('s1', 'Dit toestel', { current: true })],
      u2: [userSession('s3', 'iPhone van Sanne'), userSession('s4', 'Firefox op Windows')],
      u3: [],
      u4: [],
      u5: [userSession('s7', 'Mijn laptop', { current: true })]
    },
    fail
  });
  h.client = server.client;
  return server;
}

async function open(id: string, tab?: string) {
  render(UserEditor, { props: { id, tab } });
  return screen.findByRole('heading', { level: 1 });
}

const save = () => screen.getByRole('button', { name: 'Opslaan' });
const rights = (library: string) => screen.getByRole('radiogroup', { name: `Recht op ${library}` });
const level = (library: string, name: string) => within(rights(library)).getByRole('radio', { name });
const tabLink = (name: string) =>
  within(screen.getByRole('navigation', { name: 'Onderdelen' })).getByRole('link', { name });

beforeEach(() => {
  setLocale('nl');
  h.meId = 'u1';
  h.goto.mockClear();
  h.load.mockClear();
});
afterEach(() => setLocale('en'));

describe('scherm 27, weergave', () => {
  it('toont de kop en de tab Toegang zonder gekozen niveau, en schrijft niets bij het laden', async () => {
    const server = setup();
    expect(await open('u2')).toHaveTextContent('Sanne');
    expect(screen.getByText('ingelogd op 2 toestellen')).toBeInTheDocument();
    expect(screen.getByText(/^Laatst actief: .* · iPhone van Sanne$/)).toBeInTheDocument();
    expect(tabLink('Toegang')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('radio', { name: 'Lid' })).toBeChecked();
    // De huidige rechten zijn niet te lezen: geen enkel niveau is gekozen, ook Geen niet.
    for (const name of ['Geen', 'Kijken', 'Downloaden', 'Beheren']) {
      expect(level('Films', name)).not.toBeChecked();
    }
    expect(save()).toBeDisabled();
    expect(server.writes()).toEqual([]);
  });

  it('laat de regels over toestellen weg als de sessies niet te lezen zijn', async () => {
    setup({ 'GET /sessions': apiError('server.internal', 500) });
    await open('u2');
    expect(screen.queryByText(/Laatst actief/)).not.toBeInTheDocument();
    expect(screen.queryByText(/ingelogd op/)).not.toBeInTheDocument();
  });

  it('zegt eerlijk dat de huidige rechten niet te lezen zijn', async () => {
    setup();
    await open('u2');
    expect(screen.getByText(/De server toont de rechten die Sanne nu heeft niet/)).toBeInTheDocument();
  });

  it('toont voor een beheerder geen niveaus maar de uitleg van de rol', async () => {
    setup();
    await open('u4');
    expect(screen.queryByRole('radiogroup', { name: /Recht op/ })).not.toBeInTheDocument();
    expect(screen.getByText(/komt via de rol bij elke bibliotheek/)).toBeInTheDocument();
  });

  it('toont een onbekende gebruiker als niet gevonden', async () => {
    setup();
    render(UserEditor, { props: { id: 'nope' } });
    expect(await screen.findByText('Gebruiker niet gevonden')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Terug naar gebruikers' })).toHaveAttribute('href', '/admin/users');
  });

  it('toont een melding na het toevoegen', async () => {
    setup();
    render(UserEditor, { props: { id: 'u2', added: 'Sanne' } });
    expect(await screen.findByText(/Sanne is toegevoegd/)).toBeInTheDocument();
  });
});

describe('tabs', () => {
  it('wisselt van tab, zet de query en houdt een nog niet opgeslagen keuze vast', async () => {
    setup();
    await open('u2');
    await userEvent.click(level('Films', 'Downloaden'));
    expect(screen.getByText('iPhone van Sanne')).not.toBeVisible();

    await userEvent.click(tabLink('Toestellen'));
    expect(tabLink('Toestellen')).toHaveAttribute('aria-current', 'page');
    expect(tabLink('Toegang')).not.toHaveAttribute('aria-current');
    expect(screen.getByText('iPhone van Sanne')).toBeInTheDocument();
    expect(screen.queryByRole('radiogroup')).not.toBeInTheDocument();
    expect(h.goto).toHaveBeenCalledWith('?tab=devices', { replaceState: true, reset: false });

    await userEvent.click(tabLink('Profiel'));
    expect(screen.getByRole('textbox', { name: 'Gebruikersnaam' })).toBeDisabled();
    expect(screen.getByText('iPhone van Sanne')).not.toBeVisible();

    await userEvent.click(tabLink('Toegang'));
    expect(level('Films', 'Downloaden')).toBeChecked();
    expect(save()).toBeEnabled();
  });

  it('opent de tab uit de query, en een onbekende waarde valt terug op Toegang', async () => {
    setup();
    await open('u2', 'devices');
    expect(tabLink('Toestellen')).toHaveAttribute('href', '?tab=devices');
    expect(tabLink('Toestellen')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByText('iPhone van Sanne')).toBeInTheDocument();
  });

  it('volgt de tab uit de URL als die na het laden verandert', async () => {
    setup();
    const view = render(UserEditor, { props: { id: 'u2', tab: 'profile' } });
    await screen.findByRole('heading', { level: 1 });
    expect(tabLink('Profiel')).toHaveAttribute('aria-current', 'page');
    await view.rerender({ id: 'u2', tab: 'devices' });
    expect(tabLink('Toestellen')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByText('iPhone van Sanne')).toBeVisible();
    await view.rerender({ id: 'u2', tab: null });
    expect(tabLink('Toegang')).toHaveAttribute('aria-current', 'page');
  });

  it('houdt een lopende intrekking bezig over een tabwissel heen, zonder tweede aanvraag', async () => {
    let release: (r: Response) => void = () => {};
    const pending = new Promise<Response>((resolve) => (release = resolve));
    const server = setup({ 'DELETE /sessions/s3': (() => pending) as unknown as () => Response });
    await open('u2', 'devices');
    await userEvent.click(screen.getByRole('button', { name: 'iPhone van Sanne uitloggen' }));
    await userEvent.click(tabLink('Profiel'));
    await userEvent.click(tabLink('Toestellen'));
    const button = screen.getByRole('button', { name: 'iPhone van Sanne uitloggen' });
    expect(button).toBeDisabled();
    await userEvent.click(button);
    expect(server.writes().filter((w) => w.method === 'DELETE')).toHaveLength(1);
    release(new Response(null, { status: 204 }));
  });

  it('slaat op met Enter op een keuze, en biedt Annuleren naar de lijst', async () => {
    const server = setup();
    await open('u2');
    expect(screen.getByRole('link', { name: 'Annuleren' })).toHaveAttribute('href', '/admin/users');
    await userEvent.click(screen.getByRole('radio', { name: 'Beheerder' }));
    // Enter op een keuze verstuurt in de browser het formulier via de knop Opslaan
    // in de kop (`form`-attribuut). jsdom kent die regel niet, dus de test verstuurt
    // het formulier zelf en bewijst de koppeling knop-formulier apart.
    const form = screen.getByRole('radio', { name: 'Beheerder' }).closest('form')!;
    expect(save()).toHaveAttribute('form', form.id);
    await fireEvent.submit(form);
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([{ method: 'PATCH', path: '/users/u2', body: { role: 'admin' } }])
    );
  });

  it('zet de focus op het nieuwe wachtwoord als het formulier vanuit de kop opent', async () => {
    setup();
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' }));
    await waitFor(() => expect(screen.getByLabelText('Nieuw wachtwoord', { exact: false })).toHaveFocus());
  });

  it('kent geen tab Kinderbeveiliging', async () => {
    setup();
    await open('u3', 'kinderbeveiliging');
    expect(tabLink('Toegang')).toHaveAttribute('aria-current', 'page');
    expect(screen.queryByRole('link', { name: /Kinderbeveiliging/ })).not.toBeInTheDocument();
  });

  it('houdt verwijderen onder elke tab bereikbaar', async () => {
    setup();
    await open('u2', 'profile');
    expect(screen.getByRole('button', { name: 'Gebruiker verwijderen' })).toBeEnabled();
    await userEvent.click(tabLink('Toestellen'));
    expect(screen.getByRole('button', { name: 'Gebruiker verwijderen' })).toBeEnabled();
  });
});

describe('rol wijzigen', () => {
  it('vraagt bij een rol die rechten afneemt om bevestiging en stuurt pas daarna', async () => {
    const server = setup();
    await open('u4');
    await userEvent.click(screen.getByRole('radio', { name: 'Lid' }));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('van Beheerder naar Lid');
    expect(server.writes()).toEqual([]);

    await userEvent.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(server.writes()).toEqual([]);

    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([{ method: 'PATCH', path: '/users/u4', body: { role: 'member' } }])
    );
    expect(await screen.findByText('Beheerder2 is opgeslagen.')).toBeInTheDocument();
  });

  it('vraagt ook bij een rol die rechten geeft om bevestiging, en stuurt pas daarna', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(screen.getByRole('radio', { name: 'Beheerder' }));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(server.writes()).toEqual([]);
    expect(within(dialog).getByText(/naar Beheerder/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([{ method: 'PATCH', path: '/users/u2', body: { role: 'admin' } }])
    );
  });

  it('haalt een melding met Opnieuw proberen weg bij een tabwissel', async () => {
    setup({ 'PATCH /users/u2': new Response('{}', { status: 500 }) });
    await open('u2');
    await userEvent.click(screen.getByRole('radio', { name: 'Beheerder' }));
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    const retry = await screen.findByRole('button', { name: /Opnieuw proberen/ });
    expect(retry).toBeInTheDocument();
    await userEvent.click(tabLink('Profiel'));
    expect(screen.queryByRole('button', { name: /Opnieuw proberen/ })).not.toBeInTheDocument();
  });

  it('waarschuwt bij een eigen degradatie dat het beheer daarna dicht gaat, en laadt de sessie opnieuw', async () => {
    h.meId = 'u5';
    const server = setup();
    await open('u5');
    await userEvent.click(screen.getByRole('radio', { name: 'Lid' }));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('Dit is je eigen account');
    expect(server.writes()).toEqual([]);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() => expect(h.goto).toHaveBeenCalledWith('/'));
    expect(h.load).toHaveBeenCalled();
  });

  it('toont de eigenaar als vast: geen keuze, geen verwijderen', async () => {
    setup();
    await open('u1');
    expect(screen.queryByRole('radio')).not.toBeInTheDocument();
    expect(screen.getByText(/De rol eigenaar ligt vast/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Gebruiker verwijderen' })).toBeDisabled();
    expect(screen.getByText('De eigenaar kan niet verwijderd worden.')).toBeInTheDocument();
  });

  it('laat een serverweigering de pagina intact en toont de zin met uitweg', async () => {
    const server = setup({ 'PATCH /users/u4': apiError('auth.owner_immutable', 409) });
    await open('u4');
    await userEvent.click(screen.getByRole('radio', { name: 'Lid' }));
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('De eigenaar ligt vast');
    // Het formulier blijft zoals de beheerder het liet: de keuze en de knop.
    expect(screen.getByRole('radio', { name: 'Lid' })).toBeChecked();
    expect(save()).toBeEnabled();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(server.writes()).toHaveLength(1);
  });
});

describe('bibliotheekrechten', () => {
  it('kiest één niveau per bibliotheek en zet de rest dan op Geen', async () => {
    setup();
    await open('u2');
    await userEvent.click(level('Films', 'Downloaden'));
    expect(level('Films', 'Downloaden')).toBeChecked();
    expect(level('Films', 'Kijken')).not.toBeChecked();
    // Opslaan schrijft de hele lijst, dus de andere bibliotheek staat nu zichtbaar op Geen.
    expect(level('Series', 'Geen')).toBeChecked();
  });

  it('wijzigt een niveau en slaat het op: de laatste keuze per bibliotheek gaat naar de server', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(level('Films', 'Kijken'));
    await userEvent.click(level('Films', 'Beheren'));
    await userEvent.click(level('Series', 'Downloaden'));
    await userEvent.click(level('Series', 'Kijken'));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Films: kijken, downloaden, beheren')).toBeInTheDocument();
    expect(within(dialog).getByText('Series: kijken')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() =>
      expect(server.rightsOf('u2')).toEqual([
        { library_id: 'l1', permission: 'manage' },
        { library_id: 'l2', permission: 'view' }
      ])
    );
    expect(level('Films', 'Beheren')).toBeChecked();
    expect(level('Series', 'Kijken')).toBeChecked();
    expect(save()).toBeDisabled();
  });

  it('vervangt de rechtenlijst nooit zonder bevestiging en noemt wat er komt te staan', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(level('Films', 'Kijken'));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('vervangen');
    expect(within(dialog).getByText('Films: kijken')).toBeInTheDocument();
    expect(server.writes()).toEqual([]);

    await userEvent.click(within(dialog).getByRole('button', { name: 'Annuleren' }));
    expect(server.writes()).toEqual([]);

    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'PUT',
          path: '/users/u2/permissions',
          body: { permissions: [{ library_id: 'l1', permission: 'view' }] }
        }
      ])
    );
    expect(await screen.findByText(/zoals de server ze na het opslaan teruggaf/)).toBeInTheDocument();
  });

  it('stuurt een lege lijst alleen na een bevestiging die dat zegt', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(level('Films', 'Kijken'));
    await userEvent.click(level('Films', 'Geen'));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('toegang tot geen enkele bibliotheek');
    expect(server.writes()).toEqual([]);
  });

  it('biedt een beperkte gebruiker geen Beheren aan', async () => {
    setup();
    await open('u3');
    expect(within(rights('Films')).getAllByRole('radio')).toHaveLength(3);
    expect(within(rights('Films')).queryByRole('radio', { name: 'Beheren' })).not.toBeInTheDocument();
    expect(screen.getByText(/Een beperkte gebruiker krijgt nooit Beheren/)).toBeInTheDocument();
  });

  it('klemt Beheren weg zodra de rol Beperkt wordt gekozen', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(level('Films', 'Beheren'));
    expect(level('Films', 'Beheren')).toBeChecked();
    await userEvent.click(screen.getByRole('radio', { name: 'Beperkt' }));
    expect(within(rights('Films')).queryByRole('radio', { name: 'Beheren' })).not.toBeInTheDocument();
    expect(level('Films', 'Downloaden')).toBeChecked();
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    await waitFor(() => expect(server.writes()).toHaveLength(2));
    // Eerst de rol, dan de rechten: de server toetst met de nieuwe rol.
    expect(server.writes().map((w) => w.method + ' ' + w.path)).toEqual([
      'PATCH /users/u2',
      'PUT /users/u2/permissions'
    ]);
    expect(server.rightsOf('u2')).toEqual([{ library_id: 'l1', permission: 'download' }]);
  });

  it('toont auth.permission_not_allowed als zin en houdt de keuze staan', async () => {
    setup({ 'PUT /users/u2/permissions': apiError('auth.permission_not_allowed', 409, { permission: 'manage', role: 'restricted' }) });
    await open('u2');
    await userEvent.click(level('Films', 'Beheren'));
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('krijgt nooit Beheren');
    expect(level('Films', 'Beheren')).toBeChecked();
  });

  it('wijst bij library.not_found naar opnieuw laden', async () => {
    setup({ 'PUT /users/u2/permissions': apiError('library.not_found', 404) });
    await open('u2');
    await userEvent.click(level('Films', 'Kijken'));
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('bestaat niet meer');
    expect(within(alert).getByRole('button', { name: 'Opnieuw laden' })).toBeInTheDocument();
  });
});

describe('verwijderen', () => {
  it('blokkeert zonder de exacte naam en stuurt dan één DELETE', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Gebruiker verwijderen' }));
    const dialog = await screen.findByRole('dialog');
    const confirm = within(dialog).getByRole('button', { name: 'Verwijderen' });
    expect(confirm).toBeDisabled();
    await userEvent.type(within(dialog).getByRole('textbox'), 'sanne');
    expect(confirm).toBeDisabled();
    expect(server.writes()).toEqual([]);

    await userEvent.clear(within(dialog).getByRole('textbox'));
    await userEvent.type(within(dialog).getByRole('textbox'), 'Sanne');
    await userEvent.click(confirm);
    await waitFor(() => expect(server.writes()).toEqual([{ method: 'DELETE', path: '/users/u2', body: undefined }]));
    expect(h.goto).toHaveBeenCalledWith('/admin/users?removed=Sanne');
  });

  it('laat je eigen account niet verwijderen', async () => {
    h.meId = 'u5';
    setup();
    await open('u5');
    expect(screen.getByRole('button', { name: 'Gebruiker verwijderen' })).toBeDisabled();
    expect(screen.getByText(/het account waarmee je ingelogd bent/)).toBeInTheDocument();
  });

  it('toont de weigering van de server en blijft op de pagina', async () => {
    setup({ 'DELETE /users/u2': apiError('auth.user_not_found', 404) });
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Gebruiker verwijderen' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByRole('textbox'), 'Sanne');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Verwijderen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('bestaat niet (meer)');
    expect(h.goto).not.toHaveBeenCalled();
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Sanne');
  });
});

describe('toestellen', () => {
  it('logt één toestel uit en ververst de lijst', async () => {
    const server = setup();
    await open('u2', 'devices');
    await userEvent.click(screen.getByRole('button', { name: 'iPhone van Sanne uitloggen' }));
    await waitFor(() => expect(server.writes()).toEqual([{ method: 'DELETE', path: '/sessions/s3', body: undefined }]));
    await waitFor(() => expect(screen.queryByText('iPhone van Sanne')).not.toBeInTheDocument());
    expect(screen.getByText('Firefox op Windows')).toBeInTheDocument();
  });

  it('geeft de sessie waarmee je zelf kijkt geen uitlogknop', async () => {
    h.meId = 'u5';
    setup();
    await open('u5', 'devices');
    expect(screen.getByText('dit toestel')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /uitloggen$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Overal uitloggen' })).not.toBeInTheDocument();
  });

  it('vraagt voor Overal uitloggen om bevestiging en trekt dan elke sessie in', async () => {
    const server = setup();
    await open('u2', 'devices');
    await userEvent.click(screen.getByRole('button', { name: 'Overal uitloggen' }));
    const dialog = await screen.findByRole('dialog');
    expect(server.writes()).toEqual([]);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Overal uitloggen' }));
    await waitFor(() => expect(server.writes().map((w) => w.path)).toEqual(['/sessions/s3', '/sessions/s4']));
    expect(await screen.findByText('Sanne is overal uitgelogd.')).toBeInTheDocument();
  });

  // Sinds DEC-164 stopt de rij niet meer bij de eerste fout: wie overal wil
  // uitloggen wil dat de rest ook weg is.
  it('gaat door na een weigering en zegt hoeveel er wel en niet lukte', async () => {
    const server = setup({ 'DELETE /sessions/s3': apiError('server.internal', 500) });
    await open('u2', 'devices');
    await userEvent.click(screen.getByRole('button', { name: 'Overal uitloggen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Overal uitloggen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('1 van 2 sessies van Sanne uitgelogd');
    expect(server.writes().map((w) => w.path)).toEqual(['/sessions/s3', '/sessions/s4']);
    expect(screen.getByText('iPhone van Sanne')).toBeInTheDocument();
    expect(screen.queryByText('Firefox op Windows')).not.toBeInTheDocument();
  });

  it('telt een sessie die al weg was als uitgelogd', async () => {
    setup({ 'DELETE /sessions/s3': apiError('auth.session_not_found', 404) });
    await open('u2', 'devices');
    await userEvent.click(screen.getByRole('button', { name: 'Overal uitloggen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Overal uitloggen' }));
    expect(await screen.findByText('Sanne is overal uitgelogd.')).toBeInTheDocument();
  });
});

describe('wachtwoord opnieuw instellen', () => {
  it('opent vanuit de kop de tab Profiel met het formulier', async () => {
    setup();
    await open('u2');
    expect(screen.queryByLabelText('Nieuw wachtwoord', { exact: false })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' }));
    expect(tabLink('Profiel')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByLabelText('Nieuw wachtwoord', { exact: false })).toBeInTheDocument();
  });

  it('stuurt niets voor een te kort wachtwoord', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' }));
    const field = screen.getByLabelText('Nieuw wachtwoord', { exact: false });
    await userEvent.type(field, 'kort');
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord instellen' }));
    expect(await screen.findByText('Gebruik minstens 8 tekens.')).toBeInTheDocument();
    expect(server.writes()).toEqual([]);
  });

  it('stuurt het wachtwoord alleen in de body, maakt het veld leeg en logt niets in een URL', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' }));
    const field = screen.getByLabelText('Nieuw wachtwoord', { exact: false });
    expect(field).toHaveAttribute('type', 'password');
    expect(field).toHaveAttribute('autocomplete', 'new-password');
    await userEvent.type(field, 'geheim-wachtwoord');
    await userEvent.click(screen.getByRole('button', { name: 'Wachtwoord instellen' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([
        { method: 'PATCH', path: '/users/u2', body: { password: 'geheim-wachtwoord' } }
      ])
    );
    expect(server.seen.some((s) => s.path.includes('geheim'))).toBe(false);
    expect(await screen.findByText(/Het wachtwoord van Sanne is ingesteld/)).toBeInTheDocument();
    expect(document.body.textContent).not.toContain('geheim-wachtwoord');
  });

  it('zet de knop uit voor het wachtwoord van de eigenaar, behalve voor de eigenaar zelf', async () => {
    h.meId = 'u4';
    setup();
    await open('u1', 'profile');
    expect(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' })).toBeDisabled();
    expect(screen.getByText('Alleen de eigenaar wijzigt het wachtwoord van de eigenaar.')).toBeInTheDocument();
  });
});
