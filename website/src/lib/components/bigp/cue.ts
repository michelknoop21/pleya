// Scroll moments are found by the page motion (ScrollTrigger) and delivered to the section
// that owns the Big P, as a DOM event. A section works without them: they only add a reaction.
export type Cue = { name: string; el?: Element };

export const sendCue = (target: Element, cue: Cue) => target.dispatchEvent(new CustomEvent<Cue>('bp-cue', { detail: cue }));

/** Svelte action: `use:onCue={(cue) => ...}`. */
export function onCue(node: HTMLElement, handler: (cue: Cue) => void) {
  const listen = (e: Event) => handler((e as CustomEvent<Cue>).detail);
  node.addEventListener('bp-cue', listen);
  return { destroy: () => node.removeEventListener('bp-cue', listen) };
}
