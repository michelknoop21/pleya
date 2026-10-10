/**
 * Zet het scrollen van de pagina stil zolang er een modale laag open is.
 *
 * Eén teller voor de hele pagina: staan er twee dialogen tegelijk open, dan
 * mag de eerste die sluit het scrollen niet alvast teruggeven. De klasse op
 * <html> (stijl in base.css) is een klasse en geen inline `style`, want de CSP
 * staat geen inline stijl toe. Stond de klasse er al voor de eerste vergrendeling,
 * dan blijft hij staan als de laatste loslaat.
 */
export const SCROLL_LOCK_CLASS = 'scroll-locked';

let holders = 0;
let hadClass = false;

/** Vergrendelt en geeft een functie terug die precies één keer loslaat. */
export function lockScroll(): () => void {
  const root = document.documentElement;
  if (holders === 0) {
    hadClass = root.classList.contains(SCROLL_LOCK_CLASS);
    root.classList.add(SCROLL_LOCK_CLASS);
  }
  holders += 1;

  let released = false;
  return () => {
    if (released) return;
    released = true;
    holders -= 1;
    if (holders === 0 && !hadClass) root.classList.remove(SCROLL_LOCK_CLASS);
  };
}
