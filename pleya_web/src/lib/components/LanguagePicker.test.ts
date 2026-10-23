import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

import LanguagePicker from './LanguagePicker.svelte';
import { LOCALE_STORAGE_KEY, setLocale } from '../i18n';

// Node 26 zet een eigen, lege `localStorage` op de globale scope die die van
// jsdom overschaduwt; een eigen opslag houdt de test onafhankelijk daarvan.
function memoryStorage(): Storage {
  const data = new Map<string, string>();
  return {
    get length() {
      return data.size;
    },
    key: (index: number) => [...data.keys()][index] ?? null,
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, String(value)),
    removeItem: (key: string) => void data.delete(key),
    clear: () => data.clear()
  };
}

beforeEach(() => {
  vi.stubGlobal('localStorage', memoryStorage());
});

afterEach(() => {
  vi.unstubAllGlobals();
  setLocale('en');
});

describe('LanguagePicker', () => {
  it('toont de actieve taal en koppelt het label aan de select', () => {
    render(LanguagePicker);
    const select = screen.getByLabelText('Language');
    expect(select.tagName).toBe('SELECT');
    expect(select).toHaveValue('en');
  });

  it('toont de Nederlandse schil met Nederlands geselecteerd', () => {
    setLocale('nl');
    render(LanguagePicker);
    expect(screen.getByLabelText('Taal')).toHaveValue('nl');
  });

  it('noemt elke taal in zijn eigen taal, in beide schillen', () => {
    for (const active of ['en', 'nl'] as const) {
      setLocale(active);
      const { unmount } = render(LanguagePicker);
      const names = [...document.querySelectorAll('option')].map((o) => o.textContent);
      expect(names).toEqual(['English', 'Nederlands']);
      unmount();
    }
  });

  it('bewaart de gekozen taal en herlaadt via de geïnjecteerde stub', async () => {
    const reload = vi.fn();
    render(LanguagePicker, { props: { reload } });

    await userEvent.selectOptions(screen.getByLabelText('Language'), 'nl');

    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe('nl');
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('herlaadt niet als de gekozen taal al actief is', async () => {
    const reload = vi.fn();
    render(LanguagePicker, { props: { reload } });

    await userEvent.selectOptions(screen.getByLabelText('Language'), 'en');

    expect(reload).not.toHaveBeenCalled();
  });
});
