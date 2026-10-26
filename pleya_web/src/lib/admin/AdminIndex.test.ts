import { render, screen } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import AdminIndex from './AdminIndex.svelte';
import type { OverviewData } from './overview';
import { setLocale } from '../i18n';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const empty = { libraries: [], roots: [], scans: [], jobs: [], users: [] } as unknown as OverviewData;

describe('de mobiele beheerindex', () => {
  it('toont Onderhoud in de groep Instellingen, met het adres van scherm 35', () => {
    render(AdminIndex, { props: { data: empty } });
    const link = screen.getByRole('link', { name: /Onderhoud/ });
    expect(link).toHaveAttribute('href', '/admin/diagnostics/maintenance');
    expect(screen.getByRole('link', { name: /Diagnostiek/ })).toHaveAttribute('href', '/admin/diagnostics');
  });
});
