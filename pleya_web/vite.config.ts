import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [sveltekit()],
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
