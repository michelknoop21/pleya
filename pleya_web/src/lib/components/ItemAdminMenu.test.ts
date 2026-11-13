import { fireEvent, render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ goto: vi.fn(), admin: true, caps: {} as Record<string, boolean> }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/session.svelte.js', () => ({ session: { get canAdminister() { return h.admin; }, get capabilities() { return h.caps; } } }));
import ItemAdminMenu from './ItemAdminMenu.svelte';

beforeEach(() => { h.goto.mockReset(); h.admin = true; h.caps = { metadata_overrides: true, artwork_choices: true }; });

describe('beheeringangen op het filmdetail', () => {
  it('geeft een beheerder de ingangen naar de bestaande beheerpagina\'s met het item als parameter', async () => {
    render(ItemAdminMenu, { props: { item: { id: 'a b' } } });
    await fireEvent.click(screen.getByRole('button', { name: 'More actions' }));
    expect(screen.getAllByRole('menuitem').map(entry => entry.textContent?.trim())).toEqual(['Correct match', 'Edit metadata', 'Choose poster and background']);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Correct match' }));
    expect(h.goto).toHaveBeenLastCalledWith('/admin/metadata/match?item=a%20b');
    await fireEvent.click(screen.getByRole('button', { name: 'More actions' }));
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Choose poster and background' }));
    expect(h.goto).toHaveBeenLastCalledWith('/admin/metadata/edit?item=a%20b#artwork');
  });

  it('verbergt het menu voor een lid', () => {
    h.admin = false;
    render(ItemAdminMenu, { props: { item: { id: 'movie' } } });
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('laat een ingang weg als de server de pagina erachter niet kent', async () => {
    h.caps = {};
    render(ItemAdminMenu, { props: { item: { id: 'movie' } } });
    await fireEvent.click(screen.getByRole('button', { name: 'More actions' }));
    expect(screen.getAllByRole('menuitem')).toHaveLength(1);
  });
});
