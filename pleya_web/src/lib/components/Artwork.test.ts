import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/svelte';

import Artwork from './Artwork.svelte';
import { ApiError } from '../api/errors';

const artworkBlob = vi.fn();
vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: (...args: unknown[]) => artworkBlob(...args) } }
}));

// jsdom kent geen object-URL's; ze worden hier geteld zodat de test kan zien
// of elke gemaakte URL ook wordt ingetrokken.
const created: string[] = [];
const revoked: string[] = [];

beforeEach(() => {
  created.length = 0;
  revoked.length = 0;
  artworkBlob.mockReset();
  let counter = 0;
  URL.createObjectURL = vi.fn(() => {
    const url = `blob:test/${counter++}`;
    created.push(url);
    return url;
  });
  URL.revokeObjectURL = vi.fn((url: string) => void revoked.push(url));
});

describe('Artwork', () => {
  it('haalt de bytes op via de client en hangt ze als object-URL aan het element', async () => {
    artworkBlob.mockResolvedValue(new Blob(['bytes']));
    render(Artwork, { props: { artworkId: 'a1', alt: 'Poster', eager: true } });

    const img = await screen.findByAltText('Poster');
    expect(img).toHaveAttribute('src', created[0]);
    expect(artworkBlob).toHaveBeenCalledWith('a1', expect.any(AbortSignal));
  });

  it('trekt de object-URL in wanneer de component verdwijnt', async () => {
    artworkBlob.mockResolvedValue(new Blob(['bytes']));
    const { unmount } = render(Artwork, { props: { artworkId: 'a1', alt: 'Poster', eager: true } });

    await screen.findByAltText('Poster');
    expect(created).toHaveLength(1);

    unmount();
    expect(revoked).toEqual(created);
  });

  it('breekt de aanvraag af wanneer de kaart verdwijnt voordat de bytes binnen zijn', async () => {
    let seen: AbortSignal | null = null;
    artworkBlob.mockImplementation(
      (_id: string, signal: AbortSignal) =>
        new Promise(() => {
          seen = signal;
        })
    );

    const { unmount } = render(Artwork, { props: { artworkId: 'a1', alt: 'P', eager: true } });
    await waitFor(() => expect(seen).not.toBeNull());
    unmount();

    expect(seen!.aborted).toBe(true);
  });

  it('vraagt niets op zolang het beeld niet in beeld is geweest', () => {
    const observe = vi.fn();
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        observe = observe;
        disconnect = vi.fn();
        unobserve = vi.fn();
      }
    );

    render(Artwork, { props: { artworkId: 'a1', alt: 'P' } });

    expect(artworkBlob).not.toHaveBeenCalled();
    expect(observe).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });

  it('toont een terugvalbeeld wanneer de server de afbeelding niet heeft', async () => {
    artworkBlob.mockRejectedValue(
      new ApiError({ code: 'library.not_found', message: 'x', status: 404, retryable: false })
    );
    const { container } = render(Artwork, { props: { artworkId: 'a1', alt: 'Poster', eager: true } });

    await waitFor(() => expect(container.querySelector('.artwork__fallback')).not.toBeNull());
    expect(container.querySelector('img')).toBeNull();
  });

  it('vraagt niets op wanneer het item geen artwork heeft', async () => {
    render(Artwork, { props: { artworkId: null, alt: 'Poster', eager: true } });
    await waitFor(() => expect(artworkBlob).not.toHaveBeenCalled());
  });

  it('trekt de vorige URL in wanneer het id verandert', async () => {
    artworkBlob.mockResolvedValue(new Blob(['bytes']));
    const { rerender } = render(Artwork, { props: { artworkId: 'a1', alt: 'Poster', eager: true } });
    await screen.findByAltText('Poster');

    await rerender({ artworkId: 'a2', alt: 'Poster', eager: true });
    await waitFor(() => expect(created).toHaveLength(2));

    expect(revoked).toContain(created[0]);
    expect(revoked).not.toContain(created[1]);
  });
});
