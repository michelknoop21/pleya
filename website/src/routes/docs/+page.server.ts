import { groupedChapters, chapterMeta } from '$lib/server/manual';
import type { PageServerLoad } from './$types';

export const prerender = true;

export const load: PageServerLoad = async () => {
  const meta = chapterMeta();
  const recent = [...meta]
    .filter((chapter) => chapter.updated)
    .sort((a, b) => b.updated.localeCompare(a.updated))
    .slice(0, 4);

  return {
    groups: groupedChapters(),
    recent,
    ordinals: Object.fromEntries(meta.map((chapter, index) => [chapter.slug, index + 1]))
  };
};
