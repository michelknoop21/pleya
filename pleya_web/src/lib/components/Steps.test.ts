import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import Steps from './Steps.svelte';

const steps = ['Owner', 'Storage', 'Library', 'Scan'];

describe('Steps', () => {
  it('is een geordende lijst met een naam', () => {
    render(Steps, { props: { steps, current: 1, label: 'Setup' } });
    const list = screen.getByRole('list', { name: 'Setup' });
    expect(list.tagName).toBe('OL');
    expect(screen.getAllByRole('listitem')).toHaveLength(4);
  });

  it('markeert alleen de huidige stap met aria-current="step"', () => {
    render(Steps, { props: { steps, current: 1 } });
    const items = screen.getAllByRole('listitem');
    expect(items[1]).toHaveAttribute('aria-current', 'step');
    expect(items[1]).toHaveClass('st--on');
    [0, 2, 3].forEach((i) => expect(items[i]).not.toHaveAttribute('aria-current'));
  });

  it('tekent afgeronde stappen met een vinkje en zegt dat ook in tekst', () => {
    render(Steps, { props: { steps, current: 2 } });
    const items = screen.getAllByRole('listitem');
    expect(items[0]).toHaveClass('st--done');
    expect(items[0]!.querySelector('svg')).not.toBeNull();
    expect(items[0]).toHaveTextContent('Owner, done');
    expect(items[2]).not.toHaveClass('st--done');
    expect(items[3]).toHaveTextContent('4');
    expect(items[3]).not.toHaveTextContent('done');
  });

  it('gebruikt een standaardnaam uit de catalogus', () => {
    render(Steps, { props: { steps, current: 0 } });
    expect(screen.getByRole('list', { name: 'Progress' })).toBeInTheDocument();
  });
});
