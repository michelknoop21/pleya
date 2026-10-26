import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';
import type { Config } from '@sveltejs/kit/vite';
import { csp } from './csp.ts';

// Pleya Web wordt als statische bundel in de Go-binary geserveerd, dus er is
// geen Node-runtime aan de andere kant: `adapter-static` in SPA-modus met
// `index.html` als terugval. De Go-laag serveert datzelfde bestand voor elk
// pad dat geen bestand is en niet onder een protocolprefix valt.
//
// De CSP staat in csp.ts en niet in Go. SvelteKit schrijft één bootstrapscript
// inline in de gegenereerde HTML; met `mode: 'hash'` zet hij de hash daarvan in
// een meta-tag. Twee policies worden door de browser doorsneden, dus een
// Go-header met `script-src 'self'` zou datzelfde script alsnog blokkeren. De
// Go-laag stuurt daarom alleen wat een meta-tag niet kan (`frame-ancestors`) en
// de headers buiten CSP.
//
// Vanaf Kit 3 staat de Kit-config hier en niet meer in svelte.config.js. De
// opties zijn los geëxporteerd, zodat src/csp.test.ts kan nagaan dat de CSP echt
// bij de plugin terechtkomt.
export const kitOptions: Config = {
  preprocess: vitePreprocess(),
  adapter: adapter({
    pages: 'build',
    assets: 'build',
    fallback: 'index.html',
    precompress: false,
    strict: true
  }),
  csp
};

export default defineConfig({
  plugins: [sveltekit(kitOptions)],
  server: {
    port: 5173,
    // In ontwikkeling praat de bundel met een echte Pleya Server. In de
    // uitrol staan ze op dezelfde origin, dus de client gebruikt altijd
    // relatieve paden en heeft nooit CORS nodig; deze proxy houdt dat waar.
    proxy: {
      '/pleya': {
        target: process.env.PLEYA_SERVER_ORIGIN ?? 'http://127.0.0.1:8832',
        changeOrigin: false
      }
    }
  },
  test: {
    projects: [
      {
        extends: true,
        // Svelte 5 levert twee bouwsels: een voor de server en een voor de
        // browser. jsdom is een browser, dus zonder deze conditie krijgen
        // componenttests de servervariant en rendert er niets.
        resolve: { conditions: ['browser'] },
        test: {
          name: 'unit',
          environment: 'jsdom',
          globals: true,
          setupFiles: ['./vitest-setup.ts'],
          include: ['src/**/*.test.ts'],
          restoreMocks: true
        }
      }
    ]
  }
});
