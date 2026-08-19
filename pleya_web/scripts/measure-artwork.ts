/**
 * De artworkmeting uit acceptatiecriterium 6 van PS-3W.
 *
 * De vraag is niet of blob-URL's werken, maar of ze op schaal houdbaar zijn.
 * Onderdeel 4.2 van het voorstel noemt drie voorwaarden, en alle drie moeten
 * waar zijn:
 *
 *   1. het browsergeheugen stabiliseert nadat afbeeldingen buiten beeld zijn
 *      opgeruimd, in plaats van monotoon door te groeien;
 *   2. luie laadstrategie blijft mogelijk via IntersectionObserver;
 *   3. tien keer heen en weer navigeren tussen twee grote rasters geeft geen
 *      structurele geheugengroei.
 *
 * Faalt er één, dan gaat de vraag uit onderdeel 2 van het voorstel naar de
 * tafel waar poort 2 ligt, met dit getal eronder. Er wordt hier niets aan het
 * protocol veranderd.
 *
 * Draaien:
 *   eval "$(scripts/e2e-stack.sh up)"
 *   bun run scripts/measure-artwork.ts
 */
import { chromium, type Page } from '@playwright/test';

const BASE = process.env['PLEYA_E2E_BASE_URL'] ?? 'http://127.0.0.1:8832';
const SETUP_CODE = process.env['PLEYA_E2E_SETUP_CODE'] ?? '';
const USERNAME = process.env['PLEYA_E2E_USER'] ?? 'e2e';
const PASSWORD = process.env['PLEYA_E2E_PASS'] ?? 'een-lang-genoeg-wachtwoord';
const TARGET_POSTERS = Number(process.env['PLEYA_MEASURE_POSTERS'] ?? 500);

interface Sample {
  label: string;
  heapMb: number;
  liveObjectUrls: number;
  images: number;
  requests: number;
}

/**
 * De JS-heap draagt de blobs niet: die leven in het geheugen van de renderer
 * buiten de heap. Wat er wél mee groeit is het aantal object-URL's dat nog
 * uitstaat, en dat is precies wat lekt wanneer de opruiming niet klopt. Deze
 * teller loopt in de pagina zelf mee, vóór de app laadt.
 */
const OBJECT_URL_PROBE = `
  (() => {
    const created = new Set();
    const make = URL.createObjectURL.bind(URL);
    const drop = URL.revokeObjectURL.bind(URL);
    URL.createObjectURL = (obj) => { const u = make(obj); created.add(u); return u; };
    URL.revokeObjectURL = (u) => { created.delete(u); drop(u); };
    Object.defineProperty(window, '__pleyaLiveObjectUrls', { get: () => created.size });
  })();
`;

async function heapMb(page: Page): Promise<number> {
  const session = await page.context().newCDPSession(page);
  await session.send('HeapProfiler.enable');
  await session.send('HeapProfiler.collectGarbage');
  const { usedSize } = (await session.send('Runtime.getHeapUsage')) as { usedSize: number };
  await session.detach();
  return usedSize / 1024 / 1024;
}

async function signIn(page: Page): Promise<void> {
  await page.goto(BASE);
  const info = await page.request.get(`${BASE}/pleya/v1/info`);
  const body = (await info.json()) as { auth: { setup_required: boolean } };

  if (body.auth.setup_required) {
    await page.waitForURL('**/setup');
    await page.getByLabel('Setup code').fill(SETUP_CODE);
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password', { exact: false }).fill(PASSWORD);
    await page.getByRole('button', { name: 'Create owner' }).click();
  } else {
    await page.waitForURL('**/login');
    await page.getByLabel('Username').fill(USERNAME);
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in' }).click();
  }
  await page.getByRole('navigation', { name: 'Primary' }).waitFor();
}

async function main(): Promise<void> {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  await page.addInitScript(OBJECT_URL_PROBE);

  let artworkRequests = 0;
  page.on('request', (req) => {
    if (req.url().includes('/pleya/v1/artwork/')) artworkRequests += 1;
  });

  await signIn(page);

  // De bibliotheek wordt uit de app zelf gehaald en niet met een losse
  // aanvraag: het accesstoken staat alleen in het geheugen van de pagina, dus
  // een aanvraag ernaast heeft geen sessie.
  await page.goto(`${BASE}/libraries`);
  await page.locator('main a[href^="/libraries/"]').first().waitFor();
  const tiles = await page
    .locator('main a[href^="/libraries/"]')
    .evaluateAll((els) =>
      els.map((el) => ({
        href: el.getAttribute('href') ?? '',
        text: (el.textContent ?? '').trim()
      }))
    );
  const counted = tiles
    .map((t) => ({ ...t, count: Number(/([\d.,]+)\s+items/.exec(t.text)?.[1]?.replace(/\D/g, '') ?? 0) }))
    .sort((a, b) => b.count - a.count);
  const largest = counted[0];
  if (!largest) throw new Error('geen bibliotheken');
  const libraryId = largest.href.split('/').pop() ?? '';

  const samples: Sample[] = [];
  const sample = async (label: string): Promise<Sample> => {
    const s: Sample = {
      label,
      heapMb: Number((await heapMb(page)).toFixed(1)),
      liveObjectUrls: await page.evaluate(
        () => (window as unknown as { __pleyaLiveObjectUrls: number }).__pleyaLiveObjectUrls
      ),
      images: await page.locator('.artwork img').count(),
      requests: artworkRequests
    };
    samples.push(s);
    return s;
  };

  // --- 1. Luie strategie: hoeveel posters staan er meteen? ----------------
  await page.goto(`${BASE}/libraries/${libraryId}`);
  await page.getByRole('listitem').first().waitFor();
  await page.waitForTimeout(1500);
  const initial = await sample('eerste scherm');

  const totalCells = await page.getByRole('listitem').count();
  console.log(`bibliotheek: ${largest.text.split('\n')[0]} (${largest.count} items)`);
  console.log(
    `luie strategie: ${initial.images} van ${totalCells} cellen geladen na het eerste scherm, ` +
      `${initial.requests} artwork-aanvragen`
  );

  // --- 2. Doorscrollen tot het doelaantal --------------------------------
  // Stappen van anderhalf scherm, niet van tien. Een IntersectionObserver
  // rapporteert per frame, dus een cel die tussen twee frames voorbijvliegt
  // wordt nooit als zichtbaar gezien en laadt niet. Dat is in de app geen
  // probleem — hij laadt zodra je stilstaat — maar een meting die de helft
  // overslaat meet de helft.
  const t0 = Date.now();
  let loaded = initial.images;
  let stalled = 0;
  for (let step = 0; step < 400 && loaded < TARGET_POSTERS && stalled < 12; step++) {
    await page.mouse.wheel(0, 1400);
    await page.waitForTimeout(220);
    const now = await page.locator('.artwork img').count();
    stalled = now === loaded ? stalled + 1 : 0;
    loaded = now;
  }
  const scrollMs = Date.now() - t0;
  const full = await sample(`${loaded} posters in beeld geweest`);

  console.log(
    `laden: ${loaded} posters in ${(scrollMs / 1000).toFixed(1)} s, ` +
      `${full.requests} aanvragen, heap ${full.heapMb} MB, ` +
      `${full.liveObjectUrls} object-URL's in leven`
  );

  // --- 3. Weg navigeren en opruimen --------------------------------------
  await page.goto(`${BASE}/server`);
  await page.waitForTimeout(1000);
  const after = await sample('na weg navigeren');
  console.log(
    `na weg navigeren: heap ${after.heapMb} MB (was ${full.heapMb} MB), ` +
      `${after.liveObjectUrls} object-URL's in leven (waren er ${full.liveObjectUrls})`
  );

  // --- 4. Tien keer heen en weer -----------------------------------------
  // Heen en weer binnen de app, zonder herladen: een page.goto zou de hele
  // pagina weggooien en dan meet je niets over het opruimen van de component.
  const roundTrips: number[] = [];
  const liveAfterTrip: number[] = [];
  await page.goto(`${BASE}/libraries/${libraryId}`);
  for (let i = 0; i < 10; i++) {
    await page.getByRole('main').getByRole('list').last().getByRole('listitem').first().waitFor();
    await page.mouse.wheel(0, 16000);
    await page.waitForTimeout(700);
    await page.getByRole('link', { name: 'Server', exact: true }).click();
    await page.waitForTimeout(400);
    roundTrips.push(Number((await heapMb(page)).toFixed(1)));
    liveAfterTrip.push(
      await page.evaluate(
        () => (window as unknown as { __pleyaLiveObjectUrls: number }).__pleyaLiveObjectUrls
      )
    );
    await page.getByRole('link', { name: 'Libraries', exact: true }).click();
    await page.getByRole('link', { name: /items/ }).first().click();
  }
  console.log(`tien keer heen en weer, heap na elke ronde: ${roundTrips.join(', ')} MB`);
  console.log(`object-URL's in leven na elke ronde: ${liveAfterTrip.join(', ')}`);

  const firstHalf = roundTrips.slice(0, 5).reduce((a, b) => a + b, 0) / 5;
  const secondHalf = roundTrips.slice(5).reduce((a, b) => a + b, 0) / 5;
  const drift = secondHalf - firstHalf;

  console.log('');
  console.log('--- oordeel ---');
  console.log(
    `voorwaarde 1 (geheugen stabiliseert): ` +
      `${after.heapMb <= full.heapMb && after.liveObjectUrls === 0 ? 'GEHAALD' : 'NIET GEHAALD'} ` +
      `(${full.heapMb} MB en ${full.liveObjectUrls} object-URL's tijdens het raster, ` +
      `${after.heapMb} MB en ${after.liveObjectUrls} erna)`
  );
  console.log(
    `voorwaarde 2 (luie strategie): ${initial.images < totalCells ? 'GEHAALD' : 'NIET GEHAALD'} ` +
      `(${initial.images} van ${totalCells} geladen bij binnenkomst)`
  );
  const liveDrift = (liveAfterTrip.at(-1) ?? 0) - (liveAfterTrip[0] ?? 0);
  console.log(
    `voorwaarde 3 (geen drift over tien rondes): ` +
      `${Math.abs(drift) < 5 && liveDrift === 0 ? 'GEHAALD' : 'NIET GEHAALD'} ` +
      `(gemiddeld ${firstHalf.toFixed(1)} MB in ronde 1-5, ${secondHalf.toFixed(1)} MB in ronde 6-10, ` +
      `verschil ${drift.toFixed(1)} MB; object-URL's ${liveAfterTrip[0]} -> ${liveAfterTrip.at(-1)})`
  );

  await browser.close();
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
