import GithubSlugger from 'github-slugger';
import { Marked, type Tokens } from 'marked';

/**
 * A heading that ended up in the rendered HTML, used to build the on-page
 * table of contents. `level` is the raw markdown depth; the sidebar only shows
 * 2 and 3.
 */
export type Heading = { id: string; text: string; level: number };

export type RenderedMarkdown = {
  html: string;
  headings: Heading[];
  /** Screenshots the chapter asked for that have no file yet. */
  missingMedia: string[];
};

/**
 * Screenshots live in `static/docs-media/` and are written long after the text
 * is. Globbing them at build time is what lets a chapter reference an image
 * that does not exist yet without shipping a broken `<img>`.
 */
const mediaFiles = new Set(
  Object.keys(import.meta.glob('/static/docs-media/*', { eager: false })).map((path) =>
    path.replace('/static', '')
  )
);

function escapeHtml(value: string) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function stripTags(value: string) {
  return value.replace(/<[^>]+>/g, '').trim();
}

export function renderMarkdown(source: string): RenderedMarkdown {
  const slugger = new GithubSlugger();
  const headings: Heading[] = [];
  const missingMedia: string[] = [];

  const marked = new Marked({ gfm: true });

  marked.use({
    renderer: {
      heading({ tokens, depth }: Tokens.Heading) {
        const text = this.parser.parseInline(tokens);
        const id = slugger.slug(stripTags(text));
        headings.push({ id, text: stripTags(text), level: depth });
        return `<h${depth} id="${id}">${text}</h${depth}>\n`;
      },

      // A wide table must scroll inside its own box. Without the wrapper it
      // widens the whole document and the page scrolls sideways on a phone.
      table(token: Tokens.Table) {
        const row = (cells: string[]) => `<tr>\n${cells.join('')}</tr>\n`;
        const head = row(token.header.map((cell) => this.tablecell(cell) as string));
        const body = token.rows
          .map((cells) => row(cells.map((cell) => this.tablecell(cell) as string)))
          .join('');
        return (
          '<div class="table-scroll">\n<table>\n<thead>\n' +
          head +
          '</thead>\n' +
          (body ? `<tbody>${body}</tbody>\n` : '') +
          '</table>\n</div>\n'
        );
      },

      // Images are always documentation screenshots, so they render as a
      // figure with the alt text as the caption. When the file is not there
      // yet the same slot becomes a placeholder that names the missing path.
      image({ href, text }: Tokens.Image) {
        const caption = escapeHtml(text ?? '');
        if (!href) return '';
        if (mediaFiles.has(href)) {
          return (
            `<figure class="shot">` +
            `<img src="${escapeHtml(href)}" alt="${caption}" loading="lazy" decoding="async" />` +
            (caption ? `<figcaption>${caption}</figcaption>` : '') +
            `</figure>`
          );
        }
        missingMedia.push(href);
        return (
          `<figure class="shot shot-pending" aria-label="Screenshot pending">` +
          `<div class="shot-slot" role="img" aria-label="${caption || 'Screenshot pending'}">` +
          `<svg viewBox="0 0 24 24" aria-hidden="true" width="28" height="28"><path fill="currentColor" d="M5 21q-.825 0-1.412-.587T3 19V5q0-.825.588-1.412T5 3h14q.825 0 1.413.588T21 5v14q0 .825-.587 1.413T19 21zm1-4h12l-3.75-5l-3 4L9 13z"/></svg>` +
          `</div>` +
          (caption ? `<figcaption>${caption}</figcaption>` : '') +
          `<p class="shot-path"><code>${escapeHtml(href)}</code></p>` +
          `</figure>`
        );
      }
    }
  });

  const html = marked.parse(source, { async: false }) as string;
  return { html, headings, missingMedia };
}
