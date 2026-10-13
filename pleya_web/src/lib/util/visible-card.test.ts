import { describe, expect, it } from "vitest";
import { centralVisibleCard } from "./visible-card";

describe("touch artwork selection", () => {
  it("selects the centre column rather than the first card in a row", () => {
    const cards = [0, 200, 400].map((left) => ({
      left,
      top: 100,
      width: 180,
      height: 300,
    }));
    expect(centralVisibleCard(cards, 600, 600)).toBe(cards[1]);
    expect(centralVisibleCard(cards, 200, 600)).toBe(cards[0]);
  });
  it("excludes mostly offscreen cards and clears an empty list", () => {
    expect(
      centralVisibleCard(
        [{ left: -150, top: 0, width: 180, height: 300 }],
        600,
        600,
      ),
    ).toBeUndefined();
    expect(centralVisibleCard([], 600, 600)).toBeUndefined();
  });
});
