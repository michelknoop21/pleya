/**
 * Een vervangbare artwork-loader voor `Artwork.svelte`.
 *
 * De galerij en de tests hebben beeld nodig zonder server en zonder
 * TMDb-beelden in git. Een Svelte-context houdt dat buiten de props van elke
 * kaart: productie zet de context nergens, dus daar is het gedrag ongewijzigd
 * en geldt `session.client.artworkBlob`.
 */
import { getContext, setContext } from 'svelte';

export type ArtworkLoader = (
  id: string,
  signal: AbortSignal,
  width?: number,
) => Promise<Blob>;

export const ARTWORK_LOADER_KEY = Symbol('pleya.artworkLoader');

/** Aanroepen tijdens de initialisatie van een ouder-component. */
export function setArtworkLoader(loader: ArtworkLoader): void {
  setContext(ARTWORK_LOADER_KEY, loader);
}

export function getArtworkLoader(): ArtworkLoader | undefined {
  return getContext<ArtworkLoader | undefined>(ARTWORK_LOADER_KEY);
}
