/**
 * De toestelnaam en -id die Pleya Web bij inloggen meestuurt (DEC-164).
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { setLocale } from '../i18n';
import {
  DEVICE_ID_KEY,
  DEVICE_NAME_MAX,
  clampDeviceName,
  deviceFields,
  deviceId,
  deviceName,
  resetPageDeviceId,
  type DeviceStorage
} from './device';

const UA = {
  safariMac:
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15',
  chromeWindows:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  edgeWindows:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
  firefoxLinux: 'Mozilla/5.0 (X11; Linux x86_64; rv:144.0) Gecko/20100101 Firefox/144.0',
  safariIphone:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
  chromeIphone:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/141.0.7390.41 Mobile/15E148 Safari/604.1',
  firefoxAndroid: 'Mozilla/5.0 (Android 15; Mobile; rv:144.0) Gecko/144.0 Firefox/144.0',
  operaWindows:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 OPR/124.0.0.0'
};

function memory(initial: Record<string, string> = {}): DeviceStorage & { map: Map<string, string> } {
  const map = new Map(Object.entries(initial));
  return {
    map,
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => void map.set(key, value)
  };
}

const throwing: DeviceStorage = {
  getItem: () => {
    throw new Error('SecurityError');
  },
  setItem: () => {
    throw new Error('QuotaExceededError');
  }
};

beforeEach(() => {
  setLocale('nl');
  resetPageDeviceId();
});
afterEach(() => setLocale('en'));

describe('toestelnaam', () => {
  it.each([
    [UA.safariMac, 'Safari op macOS'],
    [UA.chromeWindows, 'Chrome op Windows'],
    [UA.edgeWindows, 'Edge op Windows'],
    [UA.firefoxLinux, 'Firefox op Linux'],
    [UA.safariIphone, 'Safari op iPhone'],
    [UA.chromeIphone, 'Chrome op iPhone'],
    [UA.firefoxAndroid, 'Firefox op Android'],
    [UA.operaWindows, 'Opera op Windows']
  ])('leest %s als "%s"', (userAgent, want) => {
    expect(deviceName({ userAgent })).toBe(want);
  });

  it('herkent een iPad die zich als Mac voordoet aan de aanraakpunten', () => {
    expect(deviceName({ userAgent: UA.safariMac, maxTouchPoints: 5 })).toBe('Safari op iPad');
  });

  it('geeft userAgentData voorrang op de User-Agent waar die bestaat', () => {
    expect(
      deviceName({
        userAgent: UA.chromeWindows,
        userAgentData: {
          brands: [{ brand: 'Not)A;Brand' }, { brand: 'Chromium' }, { brand: 'Microsoft Edge' }],
          platform: 'macOS',
          mobile: false
        }
      })
    ).toBe('Edge op macOS');
  });

  it('valt terug op "Browser" bij een onbekende User-Agent, en noemt het platform als dat wel bekend is', () => {
    expect(deviceName({ userAgent: 'curl/8.7.1' })).toBe('Browser');
    expect(deviceName({ userAgent: '' })).toBe('Browser');
    expect(deviceName({})).toBe('Browser');
    expect(deviceName({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Iets/1.0' })).toBe('Browser op Linux');
  });

  it('bevat nooit de volledige User-Agent', () => {
    for (const userAgent of Object.values(UA)) {
      const name = deviceName({ userAgent });
      expect(name).not.toContain('Mozilla');
      expect(name).not.toContain('AppleWebKit');
    }
  });

  it('volgt de taal van de interface', () => {
    setLocale('en');
    expect(deviceName({ userAgent: UA.safariMac })).toBe('Safari on macOS');
  });

  it('kapt een te lange naam af op tekens, nooit langer dan de grens (negatieve controle)', () => {
    const long = 'Ü'.repeat(DEVICE_NAME_MAX + 20);
    const clamped = clampDeviceName(long);
    expect(Array.from(clamped)).toHaveLength(DEVICE_NAME_MAX);
    expect(clampDeviceName('🎬'.repeat(DEVICE_NAME_MAX + 1))).toBe('🎬'.repeat(DEVICE_NAME_MAX));
    expect(clampDeviceName('  kort  ')).toBe('kort');
    for (const userAgent of [...Object.values(UA), 'x'.repeat(5000)]) {
      expect(Array.from(deviceName({ userAgent })).length).toBeLessThanOrEqual(DEVICE_NAME_MAX);
    }
  });
});

describe('toestel-id', () => {
  it('is een UUID met voorvoegsel en blijft hetzelfde zolang de opslag hem bewaart', () => {
    const storage = memory();
    const first = deviceId(storage);
    expect(first).toMatch(/^web-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(storage.map.get(DEVICE_ID_KEY)).toBe(first);
    resetPageDeviceId();
    // Een nieuwe pagina (uitloggen, herladen, opnieuw inloggen) leest dezelfde id.
    expect(deviceId(storage)).toBe(first);
  });

  it('twee browserprofielen krijgen elk een eigen id', () => {
    const a = deviceId(memory());
    resetPageDeviceId();
    const b = deviceId(memory());
    expect(a).not.toBe(b);
  });

  it('vervangt een bewaarde waarde die niet de juiste vorm heeft', () => {
    const storage = memory({ [DEVICE_ID_KEY]: 'gerommel' });
    const id = deviceId(storage);
    expect(id).not.toBe('gerommel');
    expect(storage.map.get(DEVICE_ID_KEY)).toBe(id);
  });

  it('werkt zonder opslag: een id voor de levensduur van de pagina, zonder fout', () => {
    const first = deviceId(throwing);
    expect(first).toMatch(/^web-/);
    expect(deviceId(throwing)).toBe(first);
    expect(deviceId(null)).toBe(first);
  });
});

describe('velden voor setup en login', () => {
  const hints = { userAgent: UA.firefoxLinux };

  it('stuurt niets zonder capabilities.sessions (negatieve controle)', () => {
    const storage = memory();
    expect(deviceFields(null, storage, hints)).toEqual({});
    expect(deviceFields(undefined, storage, hints)).toEqual({});
    expect(deviceFields({ sessions: false }, storage, hints)).toEqual({});
    expect(deviceFields({}, storage, hints)).toEqual({});
    // En schrijft dan ook geen id weg.
    expect(storage.map.size).toBe(0);
  });

  it('stuurt id en naam met de vlag', () => {
    const storage = memory();
    const fields = deviceFields({ sessions: true }, storage, hints);
    expect(fields.device_name).toBe('Firefox op Linux');
    expect(fields.device_id).toBe(storage.map.get(DEVICE_ID_KEY));
  });
});
