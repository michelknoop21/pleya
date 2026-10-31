/**
 * "Toevoegen aan" (S19). De kaart opent één dialoog in de schil: een dialoog per
 * kaart zou een raster van vijfhonderd titels vijfhonderd keer dezelfde toestand
 * geven. De melding erna staat hier ook, want de dialoog is dan al dicht.
 */
import type { Item } from '../api/types';

const MESSAGE_MS = 5000;

class AddToList {
  item = $state<Item | null>(null);
  message = $state<string | null>(null);
  #timer: ReturnType<typeof setTimeout> | undefined;

  open(item: Item): void {
    this.item = item;
  }

  close(): void {
    this.item = null;
  }

  /** Na het afmelden hoort niets van dit account nog in beeld te komen. */
  reset(): void {
    this.item = null;
    this.message = null;
    clearTimeout(this.#timer);
  }

  announce(message: string): void {
    this.message = message;
    clearTimeout(this.#timer);
    this.#timer = setTimeout(() => {
      this.message = null;
    }, MESSAGE_MS);
  }
}

export const addToList = new AddToList();
