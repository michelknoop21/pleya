import { chapterMeta } from '$lib/server/manual';
import type { RequestHandler } from './$types';

export const prerender = true;

const SITE = 'https://pleya.app';

/**
 * Generated rather than kept by hand. The previous static sitemap listed two
 * URLs and never learned about anything added after it, which is exactly the
 * failure mode a twenty-chapter manual would repeat.
 */
export const GET: RequestHandler = async () => {
  const urls = [
    { loc: '/', priority: '1.0' },
    { loc: '/docs', priority: '0.8' },
    { loc: '/releases', priority: '0.6' },
    { loc: '/privacy', priority: '0.3' },
    ...chapterMeta().map((chapter) => ({
      loc: `/docs/${chapter.slug}`,
      priority: '0.6',
      lastmod: chapter.updated || undefined
    }))
  ];

  const body =
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
    urls
      .map((url) => {
        const lastmod = 'lastmod' in url && url.lastmod ? `    <lastmod>${url.lastmod}</lastmod>\n` : '';
        return `  <url>\n    <loc>${SITE}${url.loc}</loc>\n${lastmod}    <priority>${url.priority}</priority>\n  </url>\n`;
      })
      .join('') +
    `</urlset>\n`;

  return new Response(body, { headers: { 'content-type': 'application/xml' } });
};
