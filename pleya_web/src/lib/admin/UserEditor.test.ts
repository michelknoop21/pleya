/**
 * Scherm 27 tegen een nepserver. De nadruk ligt op de regels die schade
 * voorkomen: rechten afnemen en de rechtenlijst vervangen gaan nooit zonder
 * bevestiging, een serverweigering laat het scherm intact en toont de zin,
 * de eigenaar is niet aan te raken, en wachtwoorden gaan alleen in de body.
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

async function open(id: string) {
  render(UserEditor, { props: { id } });
  return screen.findByRole('heading', { level: 1 });
}

const save = () => screen.getByRole('button', { name: 'Opslaan' });
const box = (library: string, rung: string) => screen.getByRole('checkbox', { name: `${library}, ${rung}` });

beforeEach(() => {
  setLocale('nl');
  h.meId = 'u1';
  h.goto.mockClear();
  h.load.mockClear();
});
afterEach(() => setLocale('en'));

describe('scherm 27, weergave', () => {
  it('toont rol, bibliotheken, toestellen en account, en schrijft niets bij het laden', async () => {
    const server = setup();
    expect(await open('u2')).toHaveTextContent('Sanne');
    expect(screen.getByRole('radio', { name: 'Lid' })).toBeChecked();
    expect(screen.getByText('ingelogd op 2 toestellen')).toBeInTheDocument();
    expect(screen.getByText('iPhone van Sanne')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: 'Gebruikersnaam' })).toBeDisabled();
    expect(box('Films', 'Kijken')).not.toBeChecked();
    expect(save()).toBeDisabled();
    expect(server.writes()).toEqual([]);
  });

  it('zegt eerlijk dat de huidige rechten niet te lezen zijn', async () => {
    setup();
    await open('u2');
    expect(screen.getByText(/De server toont de rechten die Sanne nu heeft niet/)).toBeInTheDocument();
  });

  it('toont voor een beheerder geen vinkjes maar de uitleg van de rol', async () => {
    setup();
    await open('u4');
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
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

  it('stuurt een rol die rechten geeft zonder dialoog', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(screen.getByRole('radio', { name: 'Beheerder' }));
    await userEvent.click(save());
    await waitFor(() =>
      expect(server.writes()).toEqual([{ method: 'PATCH', path: '/users/u2', body: { role: 'admin' } }])
    );
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
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
  it('volgt de ladder: downloaden zet kijken mee, kijken weghalen haalt downloaden weg', async () => {
    setup();
    await open('u2');
    await userEvent.click(box('Films', 'Downloaden'));
    expect(box('Films', 'Kijken')).toBeChecked();
    expect(box('Films', 'Downloaden')).toBeChecked();
    await userEvent.click(box('Films', 'Kijken'));
    expect(box('Films', 'Downloaden')).not.toBeChecked();
  });

  it('vervangt de rechtenlijst nooit zonder bevestiging en noemt wat er komt te staan', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(box('Films', 'Kijken'));
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
    await userEvent.click(box('Films', 'Kijken'));
    await userEvent.click(box('Films', 'Kijken'));
    await userEvent.click(save());
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('toegang tot geen enkele bibliotheek');
    expect(server.writes()).toEqual([]);
  });

  it('zet voor een beperkte gebruiker Beheren uit', async () => {
    setup();
    await open('u3');
    expect(box('Films', 'Beheren')).toBeDisabled();
    expect(screen.getByText(/Een beperkte gebruiker krijgt nooit Beheren/)).toBeInTheDocument();
  });

  it('klemt Beheren weg zodra de rol Beperkt wordt gekozen', async () => {
    const server = setup();
    await open('u2');
    await userEvent.click(box('Films', 'Beheren'));
    expect(box('Films', 'Beheren')).toBeChecked();
    await userEvent.click(screen.getByRole('radio', { name: 'Beperkt' }));
    expect(box('Films', 'Beheren')).not.toBeChecked();
    expect(box('Films', 'Downloaden')).toBeChecked();
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

  it('toont auth.permission_not_allowed als zin en houdt de vinkjes staan', async () => {
    setup({ 'PUT /users/u2/permissions': apiError('auth.permission_not_allowed', 409, { permission: 'manage', role: 'restricted' }) });
    await open('u2');
    await userEvent.click(box('Films', 'Beheren'));
    await userEvent.click(save());
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Wijzigingen opslaan' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('krijgt nooit Beheren');
    expect(box('Films', 'Beheren')).toBeChecked();
  });

  it('wijst bij library.not_found naar opnieuw laden', async () => {
    setup({ 'PUT /users/u2/permissions': apiError('library.not_found', 404) });
    await open('u2');
    await userEvent.click(box('Films', 'Kijken'));
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
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'iPhone van Sanne uitloggen' }));
    await waitFor(() => expect(server.writes()).toEqual([{ method: 'DELETE', path: '/sessions/s3', body: undefined }]));
    await waitFor(() => expect(screen.queryByText('iPhone van Sanne')).not.toBeInTheDocument());
    expect(screen.getByText('Firefox op Windows')).toBeInTheDocument();
  });

  it('geeft de sessie waarmee je zelf kijkt geen uitlogknop', async () => {
    h.meId = 'u5';
    setup();
    await open('u5');
    expect(screen.getByText('dit toestel')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /uitloggen$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Overal uitloggen' })).not.toBeInTheDocument();
  });

  it('vraagt voor Overal uitloggen om bevestiging en trekt dan elke sessie in', async () => {
    const server = setup();
    await open('u2');
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
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Overal uitloggen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Overal uitloggen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('1 van 2 sessies van Sanne uitgelogd');
    expect(server.writes().map((w) => w.path)).toEqual(['/sessions/s3', '/sessions/s4']);
    expect(screen.getByText('iPhone van Sanne')).toBeInTheDocument();
    expect(screen.queryByText('Firefox op Windows')).not.toBeInTheDocument();
  });

  it('telt een sessie die al weg was als uitgelogd', async () => {
    setup({ 'DELETE /sessions/s3': apiError('auth.session_not_found', 404) });
    await open('u2');
    await userEvent.click(screen.getByRole('button', { name: 'Overal uitloggen' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Overal uitloggen' }));
    expect(await screen.findByText('Sanne is overal uitgelogd.')).toBeInTheDocument();
  });
});

describe('wachtwoord opnieuw instellen', () => {
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
    await open('u1');
    expect(screen.getByRole('button', { name: 'Wachtwoord opnieuw instellen' })).toBeDisabled();
    expect(screen.getByText('Alleen de eigenaar wijzigt het wachtwoord van de eigenaar.')).toBeInTheDocument();
  });
});
