import type { Config } from '@sveltejs/kit/vite';

// Geen externe host in welke directive dan ook: de bundel is
// zelfdragend en praat uitsluitend met zijn eigen origin.
export const csp: NonNullable<Config['csp']> = {
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
    // De speler (S13.2, S18.3). 'self' is direct play over
    // /pleya/v1/stream; blob: is de MediaSource-URL die hls.js aan de
    // <video> hangt, en de WebVTT-ondertitel die met de bearer binnenkomt
    // en als object-URL aan de <track> gaat. Geen worker-src: hls.js draait
    // met enableWorker uit, zodat er geen blob:-worker nodig is.
    'media-src': ['self', 'blob:'],
    'connect-src': ['self'],
    'object-src': ['none'],
    'base-uri': ['none'],
    'form-action': ['self'],
    'frame-ancestors': ['none']
  }
};
