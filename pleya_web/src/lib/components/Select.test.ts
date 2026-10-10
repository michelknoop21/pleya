import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import Select from './Select.svelte';

const options = [
  { value: '6h', label: 'Every 6 hours' },
  { value: 'daily', label: 'Daily' },
  { value: 'never', label: 'Never', disabled: true }
];

describe('Select', () => {
  it('heeft het label als naam en de hint als beschrijving', () => {
    render(Select, { props: { label: 'Scanning', options, value: '6h', hint: 'And at startup' } });
    const select = screen.getByRole('combobox', { name: 'Scanning' });
    expect(select).toHaveValue('6h');
    expect(select).toHaveAccessibleDescription('And at startup');
  });

  it('zet de keuze door en meldt hem', async () => {
    const seen: string[] = [];
    render(Select, {
      props: { label: 'Scanning', options, value: '6h', onchange: (v: string) => seen.push(v) }
    });
    const select = screen.getByRole('combobox', { name: 'Scanning' });

    await userEvent.selectOptions(select, 'daily');
    expect(select).toHaveValue('daily');
    expect(seen).toEqual(['daily']);
  });

  it('is met het toetsenbord te bereiken', async () => {
    render(Select, { props: { label: 'Scanning', options } });
    await userEvent.tab();
    expect(screen.getByRole('combobox', { name: 'Scanning' })).toHaveFocus();
  });

  it('draagt uitgeschakelde opties en een uitgeschakelde lijst', () => {
    render(Select, { props: { label: 'Scanning', options, disabled: true } });
    expect(screen.getByRole('combobox', { name: 'Scanning' })).toBeDisabled();
    expect(screen.getByRole('option', { name: 'Never' })).toBeDisabled();
  });

  it('markeert een fout met aria-invalid', () => {
    render(Select, { props: { label: 'Scanning', options, error: 'Pick a schedule' } });
    const select = screen.getByRole('combobox', { name: 'Scanning' });
    expect(select).toHaveAttribute('aria-invalid', 'true');
    expect(select).toHaveAccessibleDescription('Pick a schedule');
  });

  it('toont een lege eerste regel als er nog niets gekozen is', () => {
    render(Select, { props: { label: 'Scanning', options, placeholder: 'Choose…' } });
    expect(screen.getByRole('combobox', { name: 'Scanning' })).toHaveValue('');
  });
});
