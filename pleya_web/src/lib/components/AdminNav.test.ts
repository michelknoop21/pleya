import { render, screen, within } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import AdminNav from './AdminNav.svelte';
import MobileHeader from './MobileHeader.svelte';
import TopNav from './TopNav.svelte';
import { ADMIN_SECTIONS, activeSectionId, adminBackHref } from '../admin/sections';
import { setLocale } from '../i18n';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('de beheerzijbalk', () => {
  it('toont de tien secties van de northstar in volgorde, plus terug naar Pleya', () => {
    render(AdminNav, { props: { active: 'overview' } });
    const nav = screen.getByRole('navigation', { name: 'Serverbeheer' });
    const names = within(nav)
      .getAllByRole('link')
      .map((a) => a.textContent?.trim());
    expect(names).toEqual([
      'Overzicht',
      'Bibliotheken',
      'Opslag',
      'Scans en taken',
      'Gebruikers',
      'Media en streaming',
      'Metadata en artwork',
      'Netwerk',
      'Beveiliging',
      'Diagnostiek',
      'Terug naar Pleya'
    ]);
    expect(within(nav).getByRole('link', { name: 'Terug naar Pleya' })).toHaveAttribute('href', '/');
  });

  it('markeert precies één actieve sectie', () => {
    render(AdminNav, { props: { active: 'storage' } });
    const current = screen.getAllByRole('link').filter((a) => a.getAttribute('aria-current') === 'page');
    expect(current).toHaveLength(1);
    expect(current[0]).toHaveTextContent('Opslag');
  });

  it('geeft elke sectie een adres onder /admin, zodat geen link dood is', () => {
    for (const section of ADMIN_SECTIONS) expect(section.href.startsWith('/admin')).toBe(true);
    expect(new Set(ADMIN_SECTIONS.map((s) => s.href)).size).toBe(ADMIN_SECTIONS.length);
  });
});

describe('welke sectie bij een pad hoort', () => {
  it('kent het overzicht op /admin en op /admin/overview', () => {
    expect(activeSectionId('/admin')).toBe('overview');
    expect(activeSectionId('/admin/overview')).toBe('overview');
    expect(activeSectionId('/admin/storage')).toBe('storage');
    expect(activeSectionId('/admin/users/u1')).toBe('users');
    expect(activeSectionId('/administrator')).toBeNull();
    expect(activeSectionId('/')).toBeNull();
  });

  it('laat de mobiele terugpijl vanuit de index naar Pleya en vanuit een sectie naar de index wijzen', () => {
    expect(adminBackHref('/admin')).toBe('/');
    expect(adminBackHref('/admin/network')).toBe('/admin');
    expect(adminBackHref('/libraries')).toBeNull();
  });
});

describe('de Beheer-pil', () => {
  it('staat niet in de bovenbalk zonder beheerrecht', () => {
    render(TopNav, { props: { items: [], activeId: null } });
    expect(screen.queryByRole('link', { name: 'Beheer' })).not.toBeInTheDocument();
  });

  it('staat in de bovenbalk voor een beheerder en wijst naar /admin', () => {
    render(TopNav, { props: { items: [], activeId: null, showAdmin: true } });
    const pill = screen.getByRole('link', { name: 'Beheer' });
    expect(pill).toHaveAttribute('href', '/admin');
    expect(pill).not.toHaveAttribute('aria-current');
  });

  it('is gevuld en aria-current zodra je in beheer bent', () => {
    render(TopNav, { props: { items: [], activeId: null, showAdmin: true, adminActive: true } });
    const pill = screen.getByRole('link', { name: 'Beheer' });
    expect(pill).toHaveAttribute('aria-current', 'page');
    expect(pill).toHaveClass('admin-pill--on');
  });

  it('staat in de mobiele kop alleen met beheerrecht', () => {
    const { unmount } = render(MobileHeader, { props: {} });
    expect(screen.queryByRole('link', { name: 'Beheer' })).not.toBeInTheDocument();
    unmount();
    render(MobileHeader, { props: { showAdmin: true } });
    expect(screen.getByRole('link', { name: 'Beheer' })).toHaveAttribute('href', '/admin');
  });

  it('maakt in beheer van de mobiele kop een terugkop zonder pil', () => {
    render(MobileHeader, { props: { showAdmin: true, back: { href: '/', title: 'Serverbeheer' } } });
    expect(screen.getByRole('link', { name: 'Terug' })).toHaveAttribute('href', '/');
    expect(screen.getByText('Serverbeheer')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Beheer' })).not.toBeInTheDocument();
  });
});
