import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import Toggle from './Toggle.svelte';

describe('Toggle', () => {
  it('is een switch met het label als naam en de omschrijving apart', () => {
    render(Toggle, { props: { label: 'Allow downloads', description: 'Per user' } });
    const sw = screen.getByRole('switch', { name: 'Allow downloads' });
    expect(sw).toHaveAttribute('aria-checked', 'false');
    expect(sw).toHaveAccessibleDescription('Per user');
  });

  it('schakelt met spatie en Enter en meldt de nieuwe stand', async () => {
    const seen: boolean[] = [];
    render(Toggle, { props: { label: 'Allow downloads', onchange: (v: boolean) => seen.push(v) } });
    const sw = screen.getByRole('switch', { name: 'Allow downloads' });

    await userEvent.tab();
    expect(sw).toHaveFocus();
    await userEvent.keyboard(' ');
    expect(sw).toHaveAttribute('aria-checked', 'true');
    await userEvent.keyboard('{Enter}');
    expect(sw).toHaveAttribute('aria-checked', 'false');
    expect(seen).toEqual([true, false]);
  });

  it('schakelt ook bij een klik op het label', async () => {
    render(Toggle, { props: { label: 'Allow downloads', checked: true } });
    await userEvent.click(screen.getByText('Allow downloads'));
    expect(screen.getByRole('switch', { name: 'Allow downloads' })).toHaveAttribute(
      'aria-checked',
      'false'
    );
  });

  it('blijft staan als hij uitgeschakeld is', async () => {
    const seen: boolean[] = [];
    render(Toggle, {
      props: { label: 'Allow downloads', disabled: true, onchange: (v: boolean) => seen.push(v) }
    });
    const sw = screen.getByRole('switch', { name: 'Allow downloads' });
    expect(sw).toBeDisabled();

    await userEvent.click(sw);
    expect(sw).toHaveAttribute('aria-checked', 'false');
    expect(seen).toEqual([]);
  });
});
