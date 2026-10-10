import { describe, expect, it, vi } from 'vitest';

const environment = vi.hoisted(() => ({ dev: true }));
vi.mock('$app/environment', () => environment);

import { load } from './+page';

describe('galerijbewaking', () => {
  it('laat de galerij in ontwikkeling door', () => {
    environment.dev = true;
    expect(() => load()).not.toThrow();
  });

  it('geeft buiten ontwikkeling een 404', () => {
    environment.dev = false;
    expect(() => load()).toThrow(expect.objectContaining({ status: 404 }));
  });
});
