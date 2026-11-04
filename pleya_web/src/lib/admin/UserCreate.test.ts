/**
 * Gebruiker toevoegen tegen een nepserver: de invoer wordt vooraf gecontroleerd
 * (de server geeft voor een kort wachtwoord dezelfde 404 als voor een
 * onbekende gebruiker), de eigenaar is niet te kiezen, en een bezette naam
 * komt als zin terug zonder het formulier te legen.
 */
import { render, screen, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import { library, user, userFake } from './userFake';

const h = vi.hoisted(() => ({ client: null as unknown, goto: vi.fn(async () => {}) }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/session.svelte', () => ({
  session: {
    get client() {
      return h.client;
    }
  }
}));

import UserCreate from './UserCreate.svelte';

function setup() {
  const server = userFake({ users: [user('u1', 'Michel', 'owner')], libraries: [library('l1', 'Films')] });
  h.client = server.client;
  return server;
}

beforeEach(() => {
  setLocale('nl');
  h.goto.mockClear();
});
afterEach(() => setLocale('en'));

describe('gebruiker toevoegen', () => {
  it('biedt geen eigenaar aan en zet het wachtwoordveld op new-password', () => {
    setup();
    render(UserCreate);
    expect(screen.queryByRole('radio', { name: 'Eigenaar' })).not.toBeInTheDocument();
    expect(screen.getAllByRole('radio').map((r) => (r as HTMLInputElement).labels?.[0]?.textContent)).toHaveLength(3);
    expect(screen.getByLabelText('Wachtwoord', { exact: true })).toHaveAttribute('autocomplete', 'new-password');
  });

  it('stuurt niets zolang naam of wachtwoord niet klopt', async () => {
    const server = setup();
    render(UserCreate);
    await userEvent.type(screen.getByRole('textbox', { name: /Gebruikersnaam/ }), 'Sanne');
    await userEvent.type(screen.getByLabelText('Wachtwoord', { exact: true }), 'kort');
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));
    expect(await screen.findByText('Gebruik minstens 8 tekens.')).toBeInTheDocument();
    expect(server.writes()).toEqual([]);
  });

  it('maakt de gebruiker aan en gaat naar zijn pagina om de bibliotheken te zetten', async () => {
    const server = setup();
    render(UserCreate);
    await userEvent.type(screen.getByRole('textbox', { name: /Gebruikersnaam/ }), '  Sanne ');
    await userEvent.type(screen.getByLabelText('Wachtwoord', { exact: true }), 'een-lang-wachtwoord');
    await userEvent.click(screen.getByRole('radio', { name: 'Beperkt' }));
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));
    await waitFor(() =>
      expect(server.writes()).toEqual([
        {
          method: 'POST',
          path: '/users',
          body: { username: 'Sanne', password: 'een-lang-wachtwoord', role: 'restricted' }
        }
      ])
    );
    expect(h.goto).toHaveBeenCalledWith('/admin/users/u2?added=Sanne');
    expect(server.seen.every((s) => !s.path.includes('wachtwoord'))).toBe(true);
  });

  it('toont auth.username_taken als zin en houdt het formulier', async () => {
    setup();
    render(UserCreate);
    await userEvent.type(screen.getByRole('textbox', { name: /Gebruikersnaam/ }), 'Michel');
    await userEvent.type(screen.getByLabelText('Wachtwoord', { exact: true }), 'een-lang-wachtwoord');
    await userEvent.click(screen.getByRole('button', { name: 'Toevoegen' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('De gebruikersnaam Michel is al in gebruik');
    expect(screen.getByRole('textbox', { name: /Gebruikersnaam/ })).toHaveValue('Michel');
    expect(h.goto).not.toHaveBeenCalled();
  });
});
