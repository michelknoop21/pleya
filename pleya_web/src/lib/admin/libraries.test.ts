import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ApiError, TransportError } from '../api/errors';
import { setLocale } from '../i18n';
import {
  createBody,
  formFromLibrary,
  formValid,
  intervalOptions,
  rootChoices,
  rootsOf,
  scanSummary,
  updateBody
} from './libraries';
import { libraryProblem } from './libraryErrors';
import { library, root, scan } from './libraryFake';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const films = library('l1', 'Films', { item_count: 461, scan_interval_seconds: 21600 });
const series = library('l2', 'Series', { kind: 'shows' });
const roots = [
  root('/media/Films', films),
  root('/media/Films-4K', films),
  root('/media/Series', series),
  root('/media/vrij', null)
];

describe('roots en formulier', () => {
  it('leest de roots van een bibliotheek uit de opsomming van de server', () => {
    expect(rootsOf(roots, 'l1').map((r) => r.path)).toEqual(['/media/Films', '/media/Films-4K']);
  });

  it('markeert een root van een andere bibliotheek als bezet', () => {
    const choices = rootChoices(roots, 'l1');
    expect(choices.map((c) => c.takenBy)).toEqual([null, null, 'Series', null]);
    expect(rootChoices(roots, null).map((c) => c.takenBy)).toEqual(['Films', 'Films', 'Series', null]);
  });

  it('stuurt bij opslaan alleen wat veranderd is', () => {
    const original = formFromLibrary(films, roots);
    expect(updateBody(original, { ...original })).toEqual({});
    expect(
      updateBody(original, { ...original, title: ' Films HD ', roots: ['/media/Films'] })
    ).toEqual({ title: 'Films HD', root_paths: ['/media/Films'] });
  });

  it('zet het interval terug op de standaard met null', () => {
    const original = formFromLibrary(films, roots);
    expect(original.interval).toBe('21600');
    expect(updateBody(original, { ...original, interval: '' })).toEqual({
      scan_interval_seconds: null
    });
  });

  it('laat bij aanmaken een standaardinterval weg', () => {
    const form = { title: 'Docu', kind: 'movies', roots: ['/media/vrij'], interval: '', scanOnStart: false };
    expect(createBody(form)).toEqual({
      title: 'Docu',
      kind: 'movies',
      root_paths: ['/media/vrij'],
      scan_on_start: false
    });
    expect(createBody({ ...form, interval: '3600' }).scan_interval_seconds).toBe(3600);
  });

  it('vraagt een naam en minstens één root', () => {
    const form = { title: 'Docu', kind: 'movies', roots: ['/media/vrij'], interval: '', scanOnStart: true };
    expect(formValid(form)).toBe(true);
    expect(formValid({ ...form, title: '  ' })).toBe(false);
    expect(formValid({ ...form, roots: [] })).toBe(false);
  });

  it('geeft een interval buiten de vaste keuzes een eigen regel', () => {
    expect(intervalOptions('').map((o) => o.label)).toEqual([
      'Standaard van de server',
      'Elk uur',
      'Elke 6 uur',
      'Elke 12 uur',
      'Elke dag',
      'Elke week'
    ]);
    expect(intervalOptions('5400').map((o) => o.label)).toContain('Elke 90 minuten');
  });
});

describe('laatste scan', () => {
  const now = Date.parse('2026-10-26T09:11:00Z');

  it('zegt per toestand iets anders', () => {
    expect(scanSummary(null)).toEqual({ tone: 'idle', text: 'nog niet gescand' });
    expect(scanSummary(scan('l1', 'queued'))).toEqual({ tone: 'run', text: 'in de wachtrij' });
    expect(scanSummary(scan('l1', 'running')).text).toBe('bezig · 120 bestanden');
    expect(scanSummary(scan('l1', 'done'), now)).toEqual({ tone: 'ok', text: '1 uur geleden · 3 nieuw' });
    expect(scanSummary(scan('l1', 'failed'), now).tone).toBe('err');
  });
});

describe('foutcodes van bibliotheekbeheer', () => {
  const err = (code: string, status: number, details?: Record<string, unknown>) =>
    new ApiError({ code, message: code, status, retryable: false, ...(details ? { details } : {}) });

  it.each([
    ['storage.root_not_offered', 400, 'storage'],
    ['library.slug_taken', 409, 'none'],
    ['library.not_empty', 409, 'none'],
    ['library.config_managed', 409, 'adopt'],
    ['library.confirm_mismatch', 409, 'reload'],
    ['library.not_config_managed', 409, 'reload'],
    ['library.scan_in_progress', 409, 'activity'],
    ['library.not_found', 404, 'list'],
    ['auth.user_not_found', 404, 'home'],
    ['auth.token_expired', 401, 'login'],
    ['server.database_unavailable', 503, 'retry'],
    ['storage.full', 507, 'retry'],
    ['server.internal', 500, 'retry']
  ])('geeft %s een eigen zin met een uitweg', (code, status, wayOut) => {
    const problem = libraryProblem(err(code, status), 'Films');
    expect(problem.wayOut).toBe(wayOut);
    expect(problem.message).not.toMatch(/Er ging iets mis \(/);
  });

  it('noemt het verzoeknummer van een interne fout', () => {
    const problem = libraryProblem(err('server.internal', 500, { request_id: 'r-42' }), 'Films');
    expect(problem.message).toContain('r-42');
  });

  it('valt voor een onbekende code en een netwerkfout terug op opnieuw proberen', () => {
    expect(libraryProblem(err('library.brand_new', 409), 'Films').wayOut).toBe('retry');
    expect(libraryProblem(new TransportError(new Error('x')), 'Films')).toMatchObject({
      code: 'client.transport',
      wayOut: 'retry'
    });
  });
});
