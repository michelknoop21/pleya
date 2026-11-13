/**
 * Een melding die een navigatie overleeft: na het verwijderen van een titel
 * bestaat de detailpagina niet meer, dus de uitkomst staat op de pagina waar
 * je landt. De schil toont hem zolang je op `path` blijft en ruimt hem op
 * zodra je ergens anders heen gaat.
 */
export interface PageNotice {
  path: string;
  tone: 'info' | 'err';
  text: string;
  /** Losse regels onder de tekst, als platte tekst en nooit als HTML. */
  lines: string[];
}

export const pageNotice = $state<{ current: PageNotice | null }>({ current: null });
