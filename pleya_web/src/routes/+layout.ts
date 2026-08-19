/**
 * De hele bundel is een SPA. Er is geen Node aan de andere kant: de Go-binary
 * levert statische bestanden en één terugval op `index.html`, dus er valt
 * niets te renderen op de server en niets voor te renderen.
 */
export const ssr = false;
export const prerender = false;
export const trailingSlash = 'never';
