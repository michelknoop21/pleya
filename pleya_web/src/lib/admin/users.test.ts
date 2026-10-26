/**
 * De rekenregels van gebruikersbeheer (S10.4) en de foutzinnen. Zonder DOM: de
 * regels die bepalen wanneer een bevestiging nodig is en wat er naar de server
 * gaat, moeten los van de schermen te bewijzen zijn.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ApiError, TransportError } from '../api/errors';
import { setLocale } from '../i18n';
import { userProblem } from './userErrors';
import {
  clampForRole,
  grantLines,
  isGranted,
  isLowering,
  lastActiveText,
  librariesText,
  passwordProblem,
  permissionsBody,
  savePlan,
  toggleGrant,
  type Grants
} from './users';
import { library, userSession } from './userFake';

const films = library('l1', 'Films');
const series = library('l2', 'Series');
const libs = [films, series];

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('rollen', () => {
  it('ziet een lagere rol als afnemen en een hogere niet', () => {
    expect(isLowering('admin', 'member')).toBe(true);
    expect(isLowering('admin', 'restricted')).toBe(true);
    expect(isLowering('member', 'restricted')).toBe(true);
    expect(isLowering('member', 'admin')).toBe(false);
    expect(isLowering('restricted', 'member')).toBe(false);
    expect(isLowering('member', 'member')).toBe(false);
  });

  it('zegt "alle" voor eigenaar en beheerder en niets verzonnens voor de rest', () => {
    expect(librariesText('owner')).toBe('alle');
    expect(librariesText('admin')).toBe('alle');
    expect(librariesText('member')).toBe('per gebruiker ingesteld');
    expect(librariesText('restricted')).toBe('per gebruiker ingesteld');
  });

  it('eist minstens acht tekens voor een wachtwoord', () => {
    expect(passwordProblem('1234567')).toBe('admin.users.form.passwordShort');
    expect(passwordProblem('12345678')).toBeNull();
  });
});

describe('de rechtenladder', () => {
  it('zet bij downloaden ook kijken, en bij beheren alles', () => {
    let grants: Grants = toggleGrant({}, 'l1', 'download', true);
    expect(isGranted(grants, 'l1', 'view')).toBe(true);
    expect(isGranted(grants, 'l1', 'download')).toBe(true);
    expect(isGranted(grants, 'l1', 'manage')).toBe(false);
    grants = toggleGrant(grants, 'l1', 'manage', true);
    expect(isGranted(grants, 'l1', 'download')).toBe(true);
  });

  it('haalt bij het weghalen van kijken de hogere treden ook weg', () => {
    const grants = toggleGrant({ l1: 'manage' }, 'l1', 'view', false);
    expect(grants).toEqual({});
    expect(toggleGrant({ l1: 'manage' }, 'l1', 'download', false)).toEqual({ l1: 'view' });
  });

  it('klemt een beperkte gebruiker van beheren naar downloaden en laat anderen met rust', () => {
    const grants: Grants = { l1: 'manage', l2: 'view' };
    expect(clampForRole(grants, 'restricted')).toEqual({ l1: 'download', l2: 'view' });
    // Dezelfde verwijzing terug: een effect dat dit toewijst start zichzelf niet opnieuw.
    expect(clampForRole(grants, 'member')).toBe(grants);
    const clean: Grants = { l1: 'view' };
    expect(clampForRole(clean, 'restricted')).toBe(clean);
  });

  it('stuurt alleen bibliotheken mee die bestaan en een vinkje hebben', () => {
    const body = permissionsBody({ l1: 'download', gone: 'view' }, libs);
    expect(body).toEqual([{ library_id: 'l1', permission: 'download' }]);
    expect(grantLines({ l1: 'download' }, libs)).toEqual(['Films: kijken, downloaden']);
  });
});

describe('het opslagplan', () => {
  const base = { current: 'member', chosen: 'member', grants: {}, touched: false, libraries: libs } as const;

  it('doet niets en vraagt niets zolang er niets gewijzigd is', () => {
    const plan = savePlan(base);
    expect(plan).toEqual({ role: null, permissions: null, lowering: false, needsConfirm: false });
  });

  it('vraagt om bevestiging bij een rol die rechten afneemt', () => {
    const plan = savePlan({ ...base, current: 'admin', chosen: 'member' });
    expect(plan).toMatchObject({ role: 'member', lowering: true, needsConfirm: true });
  });

  it('vraagt niet om bevestiging bij een rol die rechten geeft', () => {
    const plan = savePlan({ ...base, chosen: 'admin' });
    expect(plan).toMatchObject({ role: 'admin', lowering: false, needsConfirm: false });
  });

  it('schrijft rechten alleen als het paneel is aangeraakt, en dan altijd na bevestiging', () => {
    expect(savePlan({ ...base, grants: { l1: 'view' } }).permissions).toBeNull();
    const plan = savePlan({ ...base, grants: { l1: 'view' }, touched: true });
    expect(plan.permissions).toEqual([{ library_id: 'l1', permission: 'view' }]);
    expect(plan.needsConfirm).toBe(true);
  });

  it('schrijft geen rechten voor wie door de rol alles ziet', () => {
    const plan = savePlan({ ...base, chosen: 'admin', grants: { l1: 'view' }, touched: true });
    expect(plan.permissions).toBeNull();
  });

  it('klemt manage weg als de nieuwe rol beperkt is', () => {
    const plan = savePlan({ ...base, chosen: 'restricted', grants: { l1: 'manage' }, touched: true });
    expect(plan.permissions).toEqual([{ library_id: 'l1', permission: 'download' }]);
  });
});

describe('laatst actief', () => {
  const now = Date.parse('2026-10-26T08:10:00Z');

  it('noemt de nieuwste sessie met haar toestel', () => {
    const text = lastActiveText(
      [
        userSession('a', 'iPhone', { last_seen_at: '2026-10-26T08:08:00Z' }),
        userSession('b', 'Apple TV', { last_seen_at: '2026-10-20T08:00:00Z' })
      ],
      now
    );
    expect(text).toContain('iPhone');
    expect(text).not.toContain('Apple TV');
  });

  it('zegt "nog nooit" zonder sessies en "onbekend" als ze niet te lezen waren', () => {
    expect(lastActiveText([], now)).toBe('nog nooit');
    expect(lastActiveText(null, now)).toBe('onbekend');
  });
});

describe('elke foutcode krijgt een zin met een uitweg', () => {
  const cases: [string, number, string, string][] = [
    ['auth.user_not_found', 404, 'Sanne', 'reload'],
    ['auth.username_taken', 409, 'Sanne', 'none'],
    ['auth.owner_immutable', 409, 'Michel', 'none'],
    ['auth.permission_not_allowed', 409, 'Kids', 'none'],
    ['library.not_found', 404, 'Sanne', 'reload'],
    ['auth.session_not_found', 404, 'Sanne', 'reload'],
    ['server.database_unavailable', 503, 'Sanne', 'retry'],
    ['storage.full', 507, 'Sanne', 'retry'],
    ['server.internal', 500, 'Sanne', 'retry'],
    ['auth.token_expired', 401, 'Sanne', 'login']
  ];

  it.each(cases)('%s', (code, status, name, wayOut) => {
    const error = new ApiError({ code, message: code, status, retryable: false });
    const problem = userProblem(error, name);
    expect(problem.code).toBe(code);
    expect(problem.wayOut).toBe(wayOut);
    expect(problem.message.length).toBeGreaterThan(20);
    // Geen kale code of rauwe sleutel in de zin.
    expect(problem.message).not.toContain('admin.users');
    expect(problem.message).not.toBe(code);
  });

  it('noemt het verzoeknummer bij server.internal', () => {
    const error = new ApiError({
      code: 'server.internal',
      message: 'x',
      status: 500,
      retryable: true,
      details: { request_id: 'req-9' }
    });
    expect(userProblem(error, 'Sanne').message).toContain('req-9');
  });

  it('valt voor een onbekende code en voor een netwerkfout terug op opnieuw proberen', () => {
    const unknown = new ApiError({ code: 'iets.nieuws', message: 'x', status: 418, retryable: false });
    expect(userProblem(unknown, 'Sanne').wayOut).toBe('retry');
    expect(userProblem(new TransportError(new Error('weg')), 'Sanne')).toMatchObject({
      code: 'client.transport',
      wayOut: 'retry'
    });
  });
});
