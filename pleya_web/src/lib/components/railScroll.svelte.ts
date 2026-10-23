/**
 * De schuifstand van een HubRail: staat het spoor aan het begin of aan het
 * eind, en kan de tabtoets er iets in bereiken. Staat los van de component, zodat HubRail over opbouw en stijl gaat
 * en dit over meten.
 */

const FOCUSABLE = 'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])';

function prefersReducedMotion(): boolean {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export class RailScroll {
  // Aan het begin staat de rij altijd op 0; of er rechts nog iets is weten we
  // pas na de eerste meting, en tot dan tonen we geen fade.
  atStart = $state(true);
  atEnd = $state(true);
  /** Of de kaarten zelf iets focusbaars bevatten; zo niet, dan neemt het spoor de tab. */
  hasFocusable = $state(true);

  #track: HTMLElement | null = null;
  #frame = 0;

  // Eén pixel speling: met een zoomfactor eindigt scrollLeft op een breuk en
  // haalt hij scrollWidth - clientWidth net niet.
  measure = (): void => {
    this.#frame = 0;
    const track = this.#track;
    if (!track) return;
    const max = track.scrollWidth - track.clientWidth;
    this.atStart = track.scrollLeft <= 1;
    this.atEnd = track.scrollLeft >= max - 1;
    this.hasFocusable = track.querySelector(FOCUSABLE) !== null;
  };

  // Een scroll-event komt tientallen keren per seconde; per frame één keer
  // meten is genoeg en houdt het schuiven soepel.
  schedule = (): void => {
    if (this.#frame) return;
    this.#frame = requestAnimationFrame(this.measure);
  };

  /** Koppelt het spoor en meet bij elke maatwijziging; geeft de opruimfunctie terug. */
  attach(track: HTMLElement): () => void {
    this.#track = track;
    this.measure();
    // De breedte verandert met het venster; dan kan de fade verschijnen of
    // verdwijnen zonder dat er gescrold is.
    const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(this.schedule) : null;
    observer?.observe(track);
    return () => {
      observer?.disconnect();
      if (this.#frame) cancelAnimationFrame(this.#frame);
      this.#frame = 0;
      this.#track = null;
    };
  }

  scrollBy(direction: -1 | 1): void {
    const track = this.#track;
    if (!track) return;
    if (direction === -1 ? this.atStart : this.atEnd) return;
    // Een JS-scroll met `smooth` negeert de CSS-regel uit base.css, dus de
    // voorkeur voor minder beweging moet hier zelf gelezen worden.
    track.scrollBy({
      left: direction * track.clientWidth * 0.8,
      behavior: prefersReducedMotion() ? 'auto' : 'smooth'
    });
  }
}
