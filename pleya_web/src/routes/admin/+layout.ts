import { adminGate } from '$lib/admin/gate';
import { session } from '$lib/stores/session.svelte';

/** Vóór er iets van beheer rendert: een lid krijgt hier zijn 404 (S10.7). */
export function load(): Promise<void> {
  return adminGate(session);
}
