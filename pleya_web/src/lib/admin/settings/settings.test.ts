/**
 * De rekenregels achter de instellingenschermen (S10.5): duren, patches die
 * alleen bevatten wat veranderde, validatie, risico's en foutzinnen.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ApiError } from '../../api/errors';
import { setLocale } from '../../i18n';
import { baseSettings } from './settingsFake';
import { draftFrom as mediaDraft, mediaPatch } from './media';
import { draftFrom as netDraft, networkPatch, validate } from './network';
import { draftFrom as secDraft, securityPatch } from './security';
import { settingsProblem } from './settingsErrors';
import {
  changeLines,
  durationLabel,
  durationOptions,
  isOrigin,
  isPublicUrl,
  mediaRisks,
  networkRisks,
  parseDuration,
  parseList,
  parseMaxStreams,
  securityRisks,
  toWireDuration
} from './settings';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

function apiFail(code: string, status: number, details: Record<string, unknown> = {}): ApiError {
  return new ApiError({ code, message: code, status, retryable: false, details });
}

describe('duren', () => {
  it('leest wat de server stuurt en wat hij accepteert', () => {
    expect(parseDuration('15m0s')).toBe(900);
    expect(parseDuration('720h0m0s')).toBe(2_592_000);
    expect(parseDuration('1h30m')).toBe(5400);
    expect(parseDuration('90s')).toBe(90);
  });

  it('weigert wat geen duur is (negatieve controle)', () => {
    for (const bad of ['', 'abc', '15', '15 minuten', 'm15', '1d']) expect(parseDuration(bad)).toBeNull();
  });

  it('stuurt de kortste vorm terug', () => {
    expect(toWireDuration(900)).toBe('15m');
    expect(toWireDuration(2_592_000)).toBe('720h');
    expect(toWireDuration(90)).toBe('90s');
  });

  it('noemt de grootste eenheid die heel uitkomt', () => {
    expect(durationLabel(900)).toBe('15 minuten');
    expect(durationLabel(7200)).toBe('2 uur');
    expect(durationLabel(2_592_000)).toBe('30 dagen');
  });

  it('zet een huidige waarde buiten de lijst er altijd bij, op volgorde', () => {
    const values = durationOptions('access_token_ttl', 20 * 60).map((o) => o.value);
    expect(values).toContain('1200');
    expect(values).toEqual([...values].sort((a, b) => Number(a) - Number(b)));
    expect(durationOptions('access_token_ttl', 900).filter((o) => o.value === '900')).toHaveLength(1);
  });
});

describe('patches', () => {
  it('is leeg zolang niets veranderd is, ook als de server "15m0s" schrijft', () => {
    const s = baseSettings();
    expect(mediaPatch(s, mediaDraft(s))).toEqual({});
    expect(securityPatch(s, secDraft(s))).toEqual({});
    expect(networkPatch(s, netDraft(s))).toEqual({});
  });

  it('bevat alleen de sleutel die veranderde', () => {
    const s = baseSettings();
    expect(securityPatch(s, { ...secDraft(s), access: '1800' })).toEqual({ access_token_ttl: '30m' });
    expect(mediaPatch(s, { ...mediaDraft(s), maxStreams: '4' })).toEqual({ max_stream_sessions: 4 });
  });

  it('laat een max buiten de grens uit de patch vallen', () => {
    const s = baseSettings();
    expect(parseMaxStreams('33')).toBeNull();
    expect(parseMaxStreams('0')).toBeNull();
    expect(parseMaxStreams('abc')).toBeNull();
    expect(mediaPatch(s, { ...mediaDraft(s), maxStreams: '99' })).toEqual({});
  });

  it('maakt een veld leeg met een lege tekst en een lijst met een lege lijst', () => {
    const s = baseSettings();
    s.cors_origins.value = ['https://a.test'];
    const patch = networkPatch(s, { ...netDraft(s), publicUrl: '', cors: '' });
    expect(patch).toEqual({ public_url: '', cors_origins: [] });
  });

  it('knipt spaties en dubbelen weg', () => {
    expect(parseList(' https://a.test\nhttps://a.test, https://b.test ')).toEqual([
      'https://a.test',
      'https://b.test'
    ]);
    const s = baseSettings();
    expect(networkPatch(s, { ...netDraft(s), name: '  Thuis  ' })).toEqual({ server_name: 'Thuis' });
  });

  it('noemt elke wijziging met label en leesbare waarde', () => {
    expect(changeLines({ access_token_ttl: '30m', cors_origins: [] })).toEqual([
      'Toegangstoken geldig: 30 minuten',
      'Toegestane origins (CORS): leeggemaakt'
    ]);
  });
});

describe('validatie van netwerk', () => {
  const s = baseSettings();
  const ok = netDraft(s);

  it('accepteert de basisinstelling', () => {
    expect(validate(ok)).toEqual({});
  });

  it('weigert een origin met pad, slot-schuine streep, inloggegevens of fout schema', () => {
    for (const bad of ['https://a.test/pad', 'https://a.test/', 'https://u:p@a.test', 'ftp://a.test', 'a.test']) {
      expect(validate({ ...ok, webOrigin: bad }).webOrigin, bad).toBeTruthy();
      expect(isOrigin(bad), bad).toBe(false);
    }
    expect(isOrigin('http://nas:8832')).toBe(true);
  });

  it('weigert een jokerteken, te veel origins en een lege of te lange naam', () => {
    expect(validate({ ...ok, cors: '*' }).cors).toBeTruthy();
    expect(validate({ ...ok, cors: Array.from({ length: 17 }, (_, i) => `https://h${i}.test`).join('\n') }).cors).toBeTruthy();
    expect(validate({ ...ok, name: '   ' }).name).toBeTruthy();
    expect(validate({ ...ok, name: 'x'.repeat(65) }).name).toBeTruthy();
  });

  it('weigert een publiek adres met inloggegevens of query', () => {
    expect(isPublicUrl('https://u:p@a.test')).toBe(false);
    expect(isPublicUrl('https://a.test?x=1')).toBe(false);
    expect(isPublicUrl('https://a.test/pleya')).toBe(true);
  });
});

describe('risico\'s', () => {
  it('waarschuwt zwaar bij een andere web-origin dan waar je nu kijkt', () => {
    const risks = networkRisks({ web_origin: 'https://nieuw.test' }, 'http://nas:8832');
    expect(risks).toHaveLength(1);
    expect(risks[0]).toMatchObject({ key: 'admin.net.risk.webOriginElsewhere', lockout: true });
  });

  it('waarschuwt bij CORS, en niet zwaar bij een naam (negatieve controle)', () => {
    expect(networkRisks({ cors_origins: ['https://a.test'] }, 'x').some((r) => r.lockout)).toBe(true);
    expect(networkRisks({ server_name: 'Thuis' }, 'x')).toEqual([]);
    expect(networkRisks({ public_url: 'https://a.test' }, 'x').every((r) => !r.lockout)).toBe(true);
  });

  it('noemt token- en sessiewijzigingen', () => {
    expect(securityRisks({ access_token_ttl: '30m' })).toHaveLength(1);
    expect(securityRisks({})).toEqual([]);
    expect(mediaRisks({ max_stream_sessions: 4 })).toHaveLength(1);
  });
});

describe('foutzinnen', () => {
  it('noemt veld en grens bij settings.invalid_value', () => {
    const p = settingsProblem(
      apiFail('settings.invalid_value', 400, { field: 'access_token_ttl', minimum: '1m', maximum: '60m' })
    );
    expect(p.message).toContain('Toegangstoken geldig');
    expect(p.message).toContain('1m tot 60m');
    expect(p.message).toContain('niets gewijzigd');
  });

  it('valt terug op een zin zonder grens, en met een onbekend veld', () => {
    expect(settingsProblem(apiFail('settings.invalid_value', 400, { field: 'web_origin' })).message).toContain(
      'Adres van de webclient'
    );
    expect(settingsProblem(apiFail('settings.invalid_value', 400)).message).toContain('een instelling');
  });

  it('heeft een uitweg bij elke code van deze routes', () => {
    expect(settingsProblem(apiFail('server.confirm_mismatch', 409), 'rotate').message).toContain('rotate');
    expect(settingsProblem(apiFail('library.not_found', 404), 'transcode', 'Sanne')).toMatchObject({
      wayOut: 'reload'
    });
    expect(settingsProblem(apiFail('auth.session_not_found', 404), 'session', 'iPhone').message).toContain('iPhone');
    expect(settingsProblem(apiFail('auth.user_not_found', 404))).toMatchObject({ wayOut: 'home' });
    expect(settingsProblem(apiFail('server.database_unavailable', 503))).toMatchObject({ wayOut: 'retry' });
    expect(settingsProblem(apiFail('storage.full', 507))).toMatchObject({ wayOut: 'retry' });
    expect(settingsProblem(apiFail('server.internal', 500, { request_id: 'req-9' })).message).toContain('req-9');
    expect(settingsProblem(apiFail('auth.token_expired', 401))).toMatchObject({ wayOut: 'login' });
  });
});
