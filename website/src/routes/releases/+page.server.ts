import { allReleases } from '$lib/server/releases';
import type { PageServerLoad } from './$types';

export const prerender = true;

export const load: PageServerLoad = async () => ({ releases: allReleases() });
