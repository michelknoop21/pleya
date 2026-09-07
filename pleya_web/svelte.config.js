import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/**
 * Pleya Web wordt als statische bundel in de Go-binary geserveerd, dus er is
 * geen Node-runtime aan de andere kant: `adapter-static` in SPA-modus met
 * `index.html` als terugval. De Go-laag serveert datzelfde bestand voor elk
 * pad dat geen bestand is en niet onder een protocolprefix valt.
 *
 * De CSP staat hier en niet in Go. SvelteKit schrijft één bootstrapscript
 * inline in de gegenereerde HTML; met `mode: 'hash'` zet hij de hash daarvan in
 * een meta-tag. Twee policies worden door de browser doorsneden, dus een
 * Go-header met `script-src 'self'` zou datzelfde script alsnog blokkeren. De
 * Go-laag stuurt daarom alleen wat een meta-tag niet kan (`frame-ancestors`) en
 * de headers buiten CSP.
 *
 * @type {import('@sveltejs/kit').Config}
 */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: 'index.html',
      precompress: false,
      strict: true
    }),
    // Geen externe host in welke directive dan ook: de bundel is
    // zelfdragend en praat uitsluitend met zijn eigen origin.
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['self'],
        'script-src': ['self'],
        // Kit zet zelf, buiten elke pagina om, een onzichtbare live-regio
        // (#svelte-announcer) neer om routewissels aan schermlezers voor te
        // lezen, en stijlt die inline via JavaScript na hydratie. `mode:
        // 'hash'` hasht alleen wat in de gegenereerde HTML zelf staat, dus
        // deze runtime-mutatie valt daarbuiten en werd tot nu toe geblokkeerd
        // (style-src-attr). Onschadelijk toen: dezelfde regel staat ook als
        // losse stylesheet-regel op #svelte-announcer, dus het element bleef
        // zichtbaar verborgen. `unsafe-hashes` is voor stijlattributen
        // verplicht naast de hash zelf (CSP3 §match-source-expression); de
        // hash hoort bij deze exacte, door Kit vastgelegde stijltekst en
        // verandert alleen als een toekomstige Kit-versie de opmaak van de
        // announcer wijzigt.
        'style-src': [
          'self',
          'unsafe-hashes',
          'sha256-S8qMpvofolR8Mpjy4kQvEm7m1q8clzU4dfDH0AmvZjo='
        ],
        'font-src': ['self'],
        // blob: is de artworkroute. GET /pleya/v1/artwork/{id} is klasse
        // authenticated en accepteert alleen een Authorization-header, en een
        // <img src> kan er geen zetten. De bytes komen dus via fetch binnen en
        // gaan als object-URL aan het element.
        'img-src': ['self', 'blob:', 'data:'],
        'connect-src': ['self'],
        'object-src': ['none'],
        'base-uri': ['none'],
        'form-action': ['self'],
        'frame-ancestors': ['none']
      }
    },
    typescript: {
      config: (cfg) => {
        cfg.include.push('../scripts/**/*.ts');
        return cfg;
      }
    }
  }
};

export default config;
