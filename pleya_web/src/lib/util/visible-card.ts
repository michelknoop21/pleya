/** Select the mostly visible card nearest the viewport centre, preserving DOM order on ties. */
export function centralVisibleCard<
  T extends { left: number; top: number; width: number; height: number },
>(cards: readonly T[], width: number, height: number): T | undefined {
  let nearest: T | undefined;
  let distance = Infinity;
  for (const card of cards) {
    const visibleWidth = Math.max(
      0,
      Math.min(width, card.left + card.width) - Math.max(0, card.left),
    );
    const visibleHeight = Math.max(
      0,
      Math.min(height, card.top + card.height) - Math.max(0, card.top),
    );
    if (visibleWidth * visibleHeight < (card.width * card.height) / 2) continue;
    const score = Math.hypot(
      card.left + card.width / 2 - width / 2,
      card.top + card.height / 2 - height / 2,
    );
    if (score < distance) {
      nearest = card;
      distance = score;
    }
  }
  return nearest;
}
