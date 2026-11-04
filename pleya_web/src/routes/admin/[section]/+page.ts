import { error } from '@sveltejs/kit';

import { sectionById } from '#lib/admin/sections.js';

/**
 * Elke sectie uit de zijbalk heeft een adres, ook als hij nog niet gebouwd is;
 * een eigen route (`admin/libraries/+page.svelte`) gaat later vóór deze. Een
 * pad dat geen sectie is, is een gewone 404.
 */
export function load({ params }: { params: { section: string } }): { section: string } {
  if (!sectionById(params.section)) error(404, 'Not Found');
  return { section: params.section };
}
