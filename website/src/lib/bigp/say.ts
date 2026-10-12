import { prefersReducedMotion } from './loop';
import type { BigP } from './rig';

/**
 * Let Big P say a line: the words appear one at a time through `onText` while his mouth
 * follows the syllables. Returns a function that cuts him off. With reduced motion the whole
 * line is shown at once and the mouth stays shut.
 */
export function say(bigp: BigP, text: string, onText: (shown: string) => void, onDone?: () => void): () => void {
  if (prefersReducedMotion()) {
    onText(text);
    onDone?.();
    return () => {};
  }
  const words = text.split(/\s+/);
  let i = 0;
  let timer: ReturnType<typeof setTimeout>;
  const next = () => {
    if (i >= words.length) {
      bigp.hush();
      onDone?.();
      return;
    }
    const word = words[i++];
    onText(words.slice(0, i).join(' '));
    // A comma or full stop gets a breath before the next word.
    timer = setTimeout(next, bigp.speak(word) + (/[,.?!…]$/.test(word) ? 260 : 60));
  };
  next();
  return () => {
    clearTimeout(timer);
    bigp.hush();
  };
}
