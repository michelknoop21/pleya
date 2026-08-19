import { defineConfig, devices } from '@playwright/test';

/**
 * De end-to-end-tests draaien tegen een echte stack, niet tegen `vite dev`.
 * Dat is het punt: ze meten of de Go-binary de bundel serveert, of de
 * protocolroutes voorrang houden, en of de flow tegen de echte API werkt.
 *
 * Zetten en opruimen doet `scripts/e2e-stack.sh`.
 */
const baseURL = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  workers: 1,
  reporter: process.env['CI'] ? 'github' : 'list',
  timeout: 30_000,
  use: {
    baseURL,
    /*
     * Geen trace en geen schermafbeelding bij een fout, en dat is geen
     * gemakzucht.
     *
     * Elke test die inlogt typt een wachtwoord in een veld. Playwright legt bij
     * een mislukte test de ARIA-boom, een schermafbeelding en een trace vast,
     * en de waarde van dat veld staat er in leesbare tekst in. Tegen de
     * wegwerpstack is dat een testwachtwoord; tegen een echte server is het een
     * credential die daarmee in `test-results/` op schijf belandt.
     *
     * Aanzetten voor foutzoeken kan bewust, en dan alleen tegen de
     * wegwerpstack: PLEYA_E2E_ARTIFACTS=1.
     */
    trace: process.env['PLEYA_E2E_ARTIFACTS'] ? 'retain-on-failure' : 'off',
    screenshot: process.env['PLEYA_E2E_ARTIFACTS'] ? 'only-on-failure' : 'off'
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // De vijf breedtes uit de responsive-strategie worden per test gezet met
    // page.setViewportSize; dit project draait de standaardbreedte.
    { name: 'mobile', use: { ...devices['Pixel 7'] } }
  ]
});
