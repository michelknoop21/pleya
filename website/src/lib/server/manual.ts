import { renderMarkdown, type Heading } from './markdown';

export type ChapterMeta = {
  slug: string;
  title: string;
  order: number;
  /** Material Symbols glyph name, drawn in the icon badge. */
  icon: string;
  summary: string;
  /** ISO date, shown as "recently updated" on the index. */
  updated: string;
  /** Sidebar grouping. Chapters keep their order inside a group. */
  group: string;
};

export type Chapter = ChapterMeta & {
  html: string;
  headings: Heading[];
  missingMedia: string[];
};

const sources = import.meta.glob('$lib/content/manual/*.md', {
  eager: true,
  query: '?raw',
  import: 'default'
}) as Record<string, string>;

/**
 * Frontmatter is a handful of `key: value` lines between `---` fences. A YAML
 * parser would be a dependency for something this small, and the manual has no
 * nested or multi-line values.
 */
function splitFrontmatter(raw: string): { data: Record<string, string>; body: string } {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(raw);
  if (!match) return { data: {}, body: raw };

  const data: Record<string, string> = {};
  for (const line of match[1].split(/\r?\n/)) {
    const at = line.indexOf(':');
    if (at === -1) continue;
    const key = line.slice(0, at).trim();
    const value = line
      .slice(at + 1)
      .trim()
      .replace(/^['"]|['"]$/g, '');
    if (key) data[key] = value;
  }
  return { data, body: raw.slice(match[0].length) };
}

function load(): Chapter[] {
  const chapters = Object.entries(sources).map(([path, raw]) => {
    const { data, body } = splitFrontmatter(raw);
    const fallbackSlug = path.split('/').pop()!.replace(/\.md$/, '');
    const rendered = renderMarkdown(body);
    return {
      slug: data.slug || fallbackSlug,
      title: data.title || fallbackSlug,
      order: Number(data.order ?? 999),
      icon: data.icon || 'article',
      summary: data.summary || '',
      updated: data.updated || '',
      group: data.group || 'Guide',
      html: rendered.html,
      headings: rendered.headings,
      missingMedia: rendered.missingMedia
    } satisfies Chapter;
  });

  return chapters.sort((a, b) => a.order - b.order);
}

const chapters = load();

export function allChapters(): Chapter[] {
  return chapters;
}

export function chapterMeta(): ChapterMeta[] {
  return chapters.map(({ html, headings, missingMedia, ...meta }) => {
    void html;
    void headings;
    void missingMedia;
    return meta;
  });
}

export function chapterBySlug(slug: string): Chapter | undefined {
  return chapters.find((chapter) => chapter.slug === slug);
}

/** Sidebar groups, in the order their first chapter appears. */
export function groupedChapters(): { group: string; chapters: ChapterMeta[] }[] {
  const groups: { group: string; chapters: ChapterMeta[] }[] = [];
  for (const chapter of chapterMeta()) {
    let bucket = groups.find((entry) => entry.group === chapter.group);
    if (!bucket) {
      bucket = { group: chapter.group, chapters: [] };
      groups.push(bucket);
    }
    bucket.chapters.push(chapter);
  }
  return groups;
}

export function neighbours(slug: string) {
  const index = chapters.findIndex((chapter) => chapter.slug === slug);
  return {
    previous: index > 0 ? chapters[index - 1] : undefined,
    next: index >= 0 && index < chapters.length - 1 ? chapters[index + 1] : undefined
  };
}
