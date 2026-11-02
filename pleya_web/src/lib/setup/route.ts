/** Only the existing setup route may be resumed after login; never a general redirect. */
export function setupDestination(next: string | null, canAdminister: boolean): string {
  return next === '/setup' && canAdminister ? '/setup' : '/';
}
