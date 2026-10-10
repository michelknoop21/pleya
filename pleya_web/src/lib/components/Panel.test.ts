import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import Panel from './Panel.svelte';

const text = (html: string) => createRawSnippet(() => ({ render: () => html }));

describe('Panel', () => {
  it('is een sectie die de titel als naam en kop draagt', () => {
    render(Panel, {
      props: { title: text('<span>Recent tasks</span>'), children: text('<p>Body</p>') }
    });
    expect(screen.getByRole('region', { name: 'Recent tasks' })).toContainElement(
      screen.getByText('Body')
    );
    expect(screen.getByRole('heading', { level: 3, name: 'Recent tasks' })).toBeInTheDocument();
  });

  it('zet de acties naast de kop, niet erin', () => {
    render(Panel, {
      props: {
        title: text('<span>Recent tasks</span>'),
        actions: text('<a href="/scans">View all</a>'),
        children: text('<p>Body</p>')
      }
    });
    const heading = screen.getByRole('heading', { name: 'Recent tasks' });
    const link = screen.getByRole('link', { name: 'View all' });
    expect(heading).not.toContainElement(link);
    expect(screen.getByRole('region', { name: 'Recent tasks' })).toContainElement(link);
  });

  it('rendert zonder titel en acties alleen de inhoud, op het gevraagde kopniveau', () => {
    const { container, unmount } = render(Panel, { props: { children: text('<p>Body</p>') } });
    expect(container.querySelector('.panel__head')).toBeNull();
    expect(container.querySelector('section')).not.toHaveAttribute('aria-labelledby');
    unmount();

    render(Panel, {
      props: {
        title: text('<span>Danger zone</span>'),
        level: 2,
        danger: true,
        flush: true,
        children: text('<p>x</p>')
      }
    });
    expect(screen.getByRole('heading', { level: 2, name: 'Danger zone' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Danger zone' })).toHaveClass(
      'panel--danger',
      'panel--flush'
    );
  });

  it('kleurt rand en titel via tone; danger blijft de oude schrijfwijze', () => {
    const { container, unmount } = render(Panel, {
      props: { title: text('<span>Maintenance</span>'), tone: 'warn', children: text('<p>x</p>') }
    });
    const section = container.querySelector('section');
    expect(section).toHaveClass('panel--warn');
    expect(section).not.toHaveClass('panel--danger');
    unmount();

    render(Panel, {
      props: { title: text('<span>Delete</span>'), tone: 'danger', children: text('<p>x</p>') }
    });
    expect(screen.getByRole('region', { name: 'Delete' })).toHaveClass('panel--danger');
  });
});
