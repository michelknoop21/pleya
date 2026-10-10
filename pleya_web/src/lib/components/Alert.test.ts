import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import Alert from './Alert.svelte';

const body = createRawSnippet(() => ({ render: () => '<span>The root is not mounted.</span>' }));
const action = createRawSnippet(() => ({ render: () => '<a href="/storage">View storage</a>' }));

describe('Alert', () => {
  it('is een beleefde statusregio bij amber, met titel en tekst', () => {
    render(Alert, { props: { title: 'Storage unreachable.', children: body } });
    const region = screen.getByRole('status');
    expect(region).toHaveClass('alert--warn');
    expect(region).toHaveTextContent('Storage unreachable. The root is not mounted.');
  });

  it('onderbreekt met role="alert" bij een fout', () => {
    render(Alert, { props: { tone: 'err', children: body } });
    expect(screen.getByRole('alert')).toHaveClass('alert--err');
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('is een statusregio bij info en zonder rol als hij niet live is', () => {
    const { unmount } = render(Alert, { props: { tone: 'info', children: body } });
    expect(screen.getByRole('status')).toHaveClass('alert--info');
    unmount();

    render(Alert, { props: { tone: 'err', live: false, children: body } });
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByText('The root is not mounted.')).toBeInTheDocument();
  });

  it('zet de actie in de regio en houdt het icoon erbuiten', () => {
    render(Alert, { props: { children: body, actions: action } });
    const region = screen.getByRole('status');
    expect(region).toContainElement(screen.getByRole('link', { name: 'View storage' }));
    expect(region.querySelector('svg')).toHaveAttribute('aria-hidden', 'true');
  });
});
