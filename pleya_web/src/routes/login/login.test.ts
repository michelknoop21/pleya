import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ error: null as string | null }));
vi.mock('#lib/stores/session.svelte.js', () => ({
  session: { get error() { return h.error; }, client: {}, capabilities: null }
}));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('$app/state', () => ({ page: { url: new URL('http://server.test/login') } }));

import Login from './+page.svelte';

beforeEach(() => {
  h.error = null;
});

describe('inlogscherm', () => {
  it('zegt waarom er niet ververst kon worden', () => {
    h.error = 'Deze server weigert het adres';
    render(Login);
    expect(screen.getByRole('alert')).toHaveTextContent('Deze server weigert het adres');
  });

  it('is leeg zonder reden', () => {
    render(Login);
    expect(screen.getByRole('alert').textContent).toBe('');
  });
});
