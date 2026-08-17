import source from '../../../../docs/RELEASES.md?raw';
import { renderMarkdown } from './markdown';

export type SectionKind = 'new' | 'improved' | 'fixed' | 'notes';

export type ReleaseSection = {
  kind: SectionKind;
  label: string;
  html: string;
  /** Top-level bullets, used for the counts on the filter. */
  count: number;
};

export type Release = {
  id: string;
  version?: string;
  build?: number;
  date?: string;
  /** ISO form of `date`, for `<time datetime>`. */
  datetime?: string;
  unreleased: boolean;
  sections: ReleaseSection[];
};

const KINDS: Record<string, { kind: SectionKind; label: string }> = {
  new: { kind: 'new', label: 'New' },
  improved: { kind: 'improved', label: 'Improved' },
  fixed: { kind: 'fixed', label: 'Fixed' },
  notes: { kind: 'notes', label: 'Notes' }
};

const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

function toIsoDate(value: string): string | undefined {
  const match = /^(\d{1,2}) ([A-Za-z]+) (\d{4})$/.exec(value.trim());
  if (!match) return undefined;
  const month = MONTHS.indexOf(match[2]);
  if (month === -1) return undefined;
  return `${match[3]}-${String(month + 1).padStart(2, '0')}-${match[1].padStart(2, '0')}`;
}

function countBullets(markdown: string) {
  return markdown.split(/\r?\n/).filter((line) => /^- /.test(line)).length;
}

function parseHeading(heading: string) {
  if (/^unreleased$/i.test(heading.trim())) {
    return { unreleased: true, id: 'unreleased' };
  }
  // "2.8.0 · build 221 · 17 August 2026"
  const parts = heading.split('·').map((part) => part.trim());
  const version = parts[0] || undefined;
  const build = Number(/(\d+)/.exec(parts[1] ?? '')?.[1]);
  const date = parts[2] || undefined;
  return {
    unreleased: false,
    id: Number.isFinite(build) ? `build-${build}` : (version ?? 'release'),
    version,
    build: Number.isFinite(build) ? build : undefined,
    date,
    datetime: date ? toIsoDate(date) : undefined
  };
}

function parseSections(body: string): ReleaseSection[] {
  const sections: ReleaseSection[] = [];
  const parts = body.split(/^### +(.+?)\s*$/m);
  // parts[0] is whatever sat above the first "###" heading; the manual entries
  // never put content there, and the anchor comment is already stripped.
  for (let i = 1; i < parts.length; i += 2) {
    const spec = KINDS[parts[i].trim().toLowerCase()];
    if (!spec) continue;
    const markdown = parts[i + 1].trim();
    if (!markdown) continue;
    sections.push({
      kind: spec.kind,
      label: spec.label,
      html: renderMarkdown(markdown).html,
      count: countBullets(markdown)
    });
  }
  return sections;
}

function parse(): Release[] {
  const parts = source.split(/^## +(.+?)\s*$/m);
  const releases: Release[] = [];

  for (let i = 1; i < parts.length; i += 2) {
    const head = parseHeading(parts[i]);
    const body = parts[i + 1]
      .replace(/^<!-- *commit:[^>]*-->\s*$/gm, '')
      .replace(/^<!-- *(BEGIN|END) GENERATED *-->\s*$/gm, '');

    const sections = parseSections(body);
    // An unreleased block with nothing in it is noise, not a release.
    if (head.unreleased && sections.length === 0) continue;
    releases.push({ ...head, sections } as Release);
  }

  return releases;
}

const releases = parse();

export function allReleases(): Release[] {
  return releases;
}

export function latestBuild(): number | undefined {
  return releases.find((release) => !release.unreleased)?.build;
}
