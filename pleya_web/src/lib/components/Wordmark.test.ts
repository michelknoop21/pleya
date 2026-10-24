import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import Wordmark from './Wordmark.svelte';

describe('Wordmark', () => {
  it('is één beeld met de merknaam, de twee lagen tellen niet mee', () => {
    const { container } = render(Wordmark);
    expect(screen.getByRole('img', { name: 'Pleya' })).toBeInTheDocument();
    // De P is decoratie binnen het beeld; een tweede naam zou "Pleya" dubbel laten voorlezen.
    expect(container.querySelector('.wm__mark')).toHaveAttribute('alt', '');
    expect(container.querySelector('.wm__text')).toHaveAttribute('aria-hidden', 'true');
  });

  it('kent de drie maten van de northstar', () => {
    const { container: nav } = render(Wordmark);
    expect(nav.querySelector('.wm')!.className).not.toMatch(/wm--(mobile|form)/);
    const { container: mobile } = render(Wordmark, { props: { size: 'mobile' } });
    expect(mobile.querySelector('.wm--mobile')).not.toBeNull();
    const { container: form } = render(Wordmark, { props: { size: 'form' } });
    expect(form.querySelector('.wm--form')).not.toBeNull();
  });
});
