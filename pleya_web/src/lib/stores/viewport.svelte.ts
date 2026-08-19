/**
 * Waar de schil van vorm wisselt.
 *
 * De app kiest tussen zijbalk en bottom bar op platform
 * (`PlatformDetector.shouldUseSideNavigation`). Een browser heeft geen platform
 * in die zin, dus web kiest op breedte, met het breekpunt `wideTablet` (900)
 * uit `ScreenBreakpoints`. De vier breekpunten zelf staan in tokens.css.
 */
export const BREAKPOINT_WIDE = 900;

class ViewportState {
  wide = $state(true);

  start(): () => void {
    if (typeof matchMedia !== 'function') return () => {};
    const query = matchMedia(`(min-width: ${BREAKPOINT_WIDE}px)`);
    this.wide = query.matches;
    const onChange = (event: MediaQueryListEvent) => {
      this.wide = event.matches;
    };
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }
}

export const viewport = new ViewportState();
