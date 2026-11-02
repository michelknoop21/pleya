import { error } from '@sveltejs/kit';
import { session } from '#lib/stores/session.svelte.js';
/** Setup stays public before the owner exists; subsequent steps are admin-only. */
export async function load():Promise<void> {
 await session.ensureStarted();
 if(session.phase==='ready' && !session.canAdminister)error(404,'Not Found');
}
