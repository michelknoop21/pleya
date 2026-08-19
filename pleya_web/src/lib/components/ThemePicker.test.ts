import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import ThemePicker from './ThemePicker.svelte';
import NavIcon from './NavIcon.svelte';
import { theme } from '../stores/theme.svelte';

describe('ThemePicker', () => {
  it('biedt dezelfde vier standen als de app en start op OLED', () => {
    render(ThemePicker);
    const select = screen.getByRole('combobox', { name: 'Theme' });
    expect(select).toHaveValue('oled');
    expect(
      [...select.querySelectorAll('option')].map((o) => o.value)
    ).toEqual(['oled', 'dark', 'light', 'system']);
  });

  it('is met het toetsenbord te bedienen en zet de keuze door', async () => {
    render(ThemePicker);
    const select = screen.getByRole('combobox', { name: 'Theme' });

    await userEvent.selectOptions(select, 'light');
    expect(theme.mode).toBe('light');
    expect(theme.palette).toBe('light');

    theme.set('oled');
  });
});

describe('NavIcon', () => {
  it('tekent de glyph inline, zodat currentColor werkt', () => {
    const { container } = render(NavIcon, { props: { name: 'home' } });
    const svg = container.querySelector('svg');
    expect(svg).not.toBeNull();
    expect(svg?.querySelector('path')?.getAttribute('fill')).toBe('currentColor');
  });

  it('is verborgen voor een schermlezer, want het label staat ernaast', () => {
    const { container } = render(NavIcon, { props: { name: 'search' } });
    expect(container.querySelector('svg')?.getAttribute('aria-hidden')).toBe('true');
  });

  it('volgt de gevraagde maat', () => {
    const { container } = render(NavIcon, { props: { name: 'library', size: 24 } });
    expect(container.querySelector('svg')?.getAttribute('width')).toBe('24');
  });
});
