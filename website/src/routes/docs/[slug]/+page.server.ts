import { error } from '@sveltejs/kit';
import { allChapters, chapterBySlug, groupedChapters, neighbours } from '$lib/server/manual';
import type { EntryGenerator, PageServerLoad } from './$types';

export const prerender = true;

export const entries: EntryGenerator = () => allChapters().map(({ slug }) => ({ slug }));

export const load: PageServerLoad = async ({ params }) => {
  const chapter = chapterBySlug(params.slug);
  if (!chapter) error(404, 'No such chapter');

  return {
    chapter,
    groups: groupedChapters(),
    ...neighbours(params.slug)
  };
};
