import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import DataTable, { type Column } from './DataTable.svelte';

interface Lib {
  id: string;
  name: string;
  kind: string;
}

const columns: Column[] = [
  { key: 'name', label: 'Library' },
  { key: 'kind', label: 'Kind' },
  { key: 'actions', label: 'Actions', align: 'end', hideLabel: true }
];

const rows: Lib[] = [
  { id: 'films', name: 'Films', kind: 'Movies' },
  { id: 'series', name: 'Series', kind: 'Shows' }
];

const cell = createRawSnippet((row: () => Lib, column: () => Column) => ({
  render: () =>
    column().key === 'actions'
      ? `<button type="button">Scan ${row().name}</button>`
      : `<span>${String(row()[column().key as keyof Lib])}</span>`
}));

describe('DataTable', () => {
  it('is een tabel met kolomkoppen met scope en een naam', () => {
    render(DataTable<Lib>, { props: { columns, rows, label: 'Libraries', cell } });
    const table = screen.getByRole('table', { name: 'Libraries' });
    const headers = within(table).getAllByRole('columnheader');
    expect(headers).toHaveLength(3);
    headers.forEach((th) => expect(th).toHaveAttribute('scope', 'col'));
    expect(headers[2]).toHaveTextContent('Actions');
    expect(within(headers[2]!).getByText('Actions')).toHaveClass('visually-hidden');
    expect(headers[2]).toHaveClass('tbl__end');
  });

  it('rendert per rij elke kolom via de cel-snippet', () => {
    render(DataTable<Lib>, {
      props: { columns, rows, label: 'Libraries', cell, rowKey: (r: Lib) => r.id }
    });
    const bodyRows = screen.getAllByRole('row').slice(1);
    expect(bodyRows).toHaveLength(2);
    expect(within(bodyRows[1]!).getByRole('button', { name: 'Scan Series' })).toBeInTheDocument();
    expect(within(bodyRows[0]!).getAllByRole('cell')[1]).toHaveTextContent('Movies');
  });

  it('valt zonder cel-snippet terug op de ruwe waarde', () => {
    render(DataTable<Lib>, { props: { columns: columns.slice(0, 2), rows, label: 'Libraries' } });
    expect(screen.getByRole('cell', { name: /Shows/ })).toBeInTheDocument();
  });

  it('scrolt binnen een benoemde regio met een tabstop', () => {
    render(DataTable<Lib>, { props: { columns, rows, label: 'Libraries', cell } });
    const region = screen.getByRole('region', { name: 'Libraries' });
    expect(region).toHaveAttribute('tabindex', '0');
    expect(region).toContainElement(screen.getByRole('table'));
  });

  it('zet in de stack-variant de kolomnaam in de cel, niet bij titel of acties', () => {
    const { container } = render(DataTable<Lib>, {
      props: { columns, rows, label: 'Libraries', cell, stack: true }
    });
    expect(screen.getByRole('table')).toHaveClass('tbl--stack');
    const cells = within(screen.getAllByRole('row')[1]!).getAllByRole('cell');
    expect(cells[0]!.querySelector('.tbl__label')).toBeNull();
    expect(cells[1]!.querySelector('.tbl__label')).toHaveTextContent('Kind');
    // Standaard alleen voor de schermlezer, niet weg uit de DOM.
    expect(cells[1]!.querySelector('.tbl__label')).toHaveClass('visually-hidden');
    expect(cells[2]!.querySelector('.tbl__label')).toBeNull();
    const strip = container.querySelector('.tbl__scroll--stack');
    expect(strip).not.toHaveAttribute('tabindex');
    expect(strip).not.toHaveAttribute('role');
  });

  it('toont de lege staat in plaats van een tabel zonder rijen', () => {
    const empty = createRawSnippet(() => ({ render: () => '<p>No libraries yet</p>' }));
    const { unmount } = render(DataTable<Lib>, {
      props: { columns, rows: [], label: 'Libraries', empty }
    });
    expect(screen.queryByRole('table')).toBeNull();
    expect(screen.getByText('No libraries yet')).toBeInTheDocument();
    unmount();

    render(DataTable<Lib>, { props: { columns, rows: [], label: 'Libraries' } });
    expect(screen.getByText('Nothing here yet.')).toBeInTheDocument();
  });

  it('hangt in een flush paneel met de titel als regionaam', () => {
    const title = createRawSnippet(() => ({ render: () => '<span>All libraries</span>' }));
    render(DataTable<Lib>, { props: { columns, rows, label: 'Libraries', cell, title } });
    expect(screen.getByRole('region', { name: 'All libraries' })).toHaveClass('panel--flush');
  });

  it('toont de kolomnaam gestapeld alleen bij showLabel', () => {
    const shown: Column[] = [
      { key: 'name', label: 'Library' },
      { key: 'kind', label: 'Kind', showLabel: true },
      { key: 'actions', label: 'Actions', align: 'end', hideLabel: true }
    ];
    render(DataTable<Lib>, {
      props: { columns: shown, rows, label: 'Libraries', cell, stack: true }
    });
    const cells = within(screen.getAllByRole('row')[1]!).getAllByRole('cell');
    const label = cells[1]!.querySelector('.tbl__label');
    expect(label).toHaveTextContent('Kind');
    expect(label).not.toHaveClass('visually-hidden');
  });
});
