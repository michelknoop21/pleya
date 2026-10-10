import { describe, expect, it } from "vitest";
import { render, screen, within } from "@testing-library/svelte";
import { createRawSnippet } from "svelte";

import StorageMeter, { type MeterSegment } from "./StorageMeter.svelte";

const tb = (v: number) => `${v} TB`;

function bar(container: HTMLElement): HTMLElement {
  return container.querySelector(".meter__bar") as HTMLElement;
}

function grows(container: HTMLElement): string[] {
  return [...bar(container).querySelectorAll<HTMLElement>(".meter__seg")].map(
    (el) => el.style.flexGrow,
  );
}

const libraries: MeterSegment[] = [
  { label: "Films", value: 46, tone: "ink" },
  { label: "Series", value: 21, tone: "amber" },
  { label: "Kids", value: 6, tone: "red" },
  { label: "Books", value: 3, tone: "blue" },
  { label: "Free", value: 24, tone: "free" },
];

describe("StorageMeter", () => {
  it("geeft elk segment zijn aandeel in procenten als flex-grow", () => {
    const { container } = render(StorageMeter, {
      props: { label: "Storage", segments: libraries },
    });
    expect(grows(container)).toEqual(["46", "21", "6", "3", "24"]);
    const tones = [...bar(container).children].map(
      (el) => el.className.match(/meter__seg--(\w+)/)?.[1],
    );
    expect(tones).toEqual(["ink", "amber", "red", "blue", "free"]);
  });

  it("laat een segment van nul uit de balk maar houdt het in de legenda", () => {
    const { container } = render(StorageMeter, {
      props: {
        label: "Storage",
        format: tb,
        segments: [
          { label: "Films", value: 3 },
          { label: "Books", value: 0, tone: "blue" },
          { label: "Free", value: 1, tone: "free" },
        ],
      },
    });
    expect(grows(container)).toEqual(["75", "25"]);
    expect(screen.getByText("Books").closest("li")).toHaveTextContent(
      "Books 0 TB",
    );
  });

  it("geeft een piepklein segment minstens één procent", () => {
    const { container } = render(StorageMeter, {
      props: {
        label: "Storage",
        segments: [
          { label: "Films", value: 9990 },
          { label: "Books", value: 1, tone: "blue" },
        ],
      },
    });
    expect(grows(container)).toEqual(["99.99", "1"]);
  });

  it("tekent de rest als vrij als total groter is dan de som", () => {
    const { container } = render(StorageMeter, {
      props: {
        label: "Storage",
        total: 16,
        segments: [{ label: "Films", value: 4 }],
      },
    });
    expect(grows(container)).toEqual(["25", "75"]);
    expect(bar(container).lastElementChild).toHaveClass("meter__seg--free");
    // De rest is beeld, geen gegeven: de legenda noemt alleen wat de aanroeper gaf.
    expect(screen.getAllByRole("listitem")).toHaveLength(1);
  });

  it("negeert een total kleiner dan de som, zodat de balk niet overloopt", () => {
    const { container } = render(StorageMeter, {
      props: {
        label: "Storage",
        total: 2,
        segments: [
          { label: "A", value: 1 },
          { label: "B", value: 3 },
        ],
      },
    });
    expect(grows(container)).toEqual(["25", "75"]);
  });

  it("leest als een benoemde lijst en houdt de balk buiten de boom", () => {
    const { container } = render(StorageMeter, {
      props: {
        label: "Storage per library",
        format: tb,
        segments: libraries.slice(0, 2),
      },
    });
    expect(bar(container)).toHaveAttribute("aria-hidden", "true");
    const list = screen.getByRole("list", { name: "Storage per library" });
    const items = within(list).getAllByRole("listitem");
    expect(items.map((li) => li.textContent?.trim())).toEqual([
      "Films 46 TB",
      "Series 21 TB",
    ]);
  });

  it("toont bij totaal nul een leeg spoor en de lege staat in plaats van de legenda", () => {
    const empty = createRawSnippet(() => ({ render: () => "<p>Unknown</p>" }));
    const { container } = render(StorageMeter, {
      props: { label: "Storage", segments: [], empty },
    });
    expect(bar(container)).toHaveClass("meter__bar--empty");
    expect(grows(container)).toEqual([]);
    expect(screen.queryByRole("list")).not.toBeInTheDocument();
    expect(screen.getByText("Unknown")).toBeInTheDocument();
  });
});
