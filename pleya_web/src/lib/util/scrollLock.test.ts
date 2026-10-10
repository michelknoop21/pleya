import { afterEach, describe, expect, it } from 'vitest';

import { SCROLL_LOCK_CLASS, lockScroll } from './scrollLock';

const root = () => document.documentElement;

afterEach(() => {
  root().classList.remove(SCROLL_LOCK_CLASS);
});

describe('lockScroll', () => {
  it('houdt de klasse vast tot de laatste houder loslaat', () => {
    const first = lockScroll();
    const second = lockScroll();
    expect(root()).toHaveClass(SCROLL_LOCK_CLASS);
    first();
    expect(root()).toHaveClass(SCROLL_LOCK_CLASS);
    second();
    expect(root()).not.toHaveClass(SCROLL_LOCK_CLASS);
  });

  it('telt een dubbele release maar één keer', () => {
    const first = lockScroll();
    const second = lockScroll();
    first();
    first();
    expect(root()).toHaveClass(SCROLL_LOCK_CLASS);
    second();
    expect(root()).not.toHaveClass(SCROLL_LOCK_CLASS);
  });

  it('laat een klasse staan die er al voor de eerste vergrendeling was', () => {
    root().classList.add(SCROLL_LOCK_CLASS);
    const release = lockScroll();
    release();
    expect(root()).toHaveClass(SCROLL_LOCK_CLASS);
  });
});
