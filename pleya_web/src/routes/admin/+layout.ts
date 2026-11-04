import { adminGate } from '#lib/admin/gate.js';
import { session } from '#lib/stores/session.svelte.js';

/** Vóór er iets van beheer rendert: een lid krijgt hier zijn 404 (S10.7). */
export function load(): Promise<void> {
  return adminGate(session);
}
