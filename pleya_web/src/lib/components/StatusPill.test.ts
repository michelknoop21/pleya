import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/svelte";
import { createRawSnippet } from "svelte";

import StatusPill from "./StatusPill.svelte";

describe("StatusPill", () => {
  it.each(["ok", "warn", "err", "run", "idle"] as const)(
    "draagt de toon %s als klasse",
    (tone) => {
      render(StatusPill, { props: { label: "state", tone } });
      expect(screen.getByText("state")).toHaveClass("pill", `pill--${tone}`);
    },
  );

  it("is standaard idle en zonder stip", () => {
    const { container } = render(StatusPill, { props: { label: "revoked" } });
    const pill = screen.getByText("revoked");
    expect(pill).toHaveClass("pill--idle");
    expect(pill).toHaveTextContent(/^revoked$/);
    expect(container.querySelector(".pill__dot")).toBeNull();
  });

  it("tekent de stip alleen op verzoek, voor een schermlezer onzichtbaar", () => {
    const { container } = render(StatusPill, {
      props: { label: "running", tone: "run", dot: true },
    });
    expect(container.querySelector(".pill__dot")).toHaveAttribute(
      "aria-hidden",
      "true",
    );
  });

  it("vervangt de stip door een icoon", () => {
    const icon = createRawSnippet(() => ({
      render: () => '<svg data-testid="check"></svg>',
    }));
    const { container } = render(StatusPill, {
      props: { label: "done", tone: "ok", dot: true, icon },
    });
    expect(container.querySelector(".pill__dot")).toBeNull();
    expect(screen.getByTestId("check")).toBeInTheDocument();
  });

  it("heeft een kleine maat voor tabelcellen", () => {
    render(StatusPill, {
      props: { label: "not mounted", tone: "err", size: "sm" },
    });
    expect(screen.getByText("not mounted")).toHaveClass("pill--sm");
  });

  it("tekent als statuscel een stip zonder capsule, ook zonder dot", () => {
    const { container } = render(StatusPill, {
      props: { label: "today 08:12", tone: "ok", variant: "dot", size: "sm" },
    });
    const pill = screen.getByText("today 08:12");
    expect(pill).toHaveClass("pill--status");
    expect(pill).not.toHaveClass("pill--sm");
    expect(container.querySelector(".pill__dot")).toHaveAttribute("aria-hidden", "true");
  });

  it("tekent run als stip met de pulsklasse en als capsule zonder stip", () => {
    const { container } = render(StatusPill, {
      props: { label: "busy", tone: "run", variant: "dot" },
    });
    const status = screen.getByText("busy");
    expect(status).toHaveClass("pill--status", "pill--run");
    expect(container.querySelector(".pill__dot")).not.toBeNull();

    render(StatusPill, { props: { label: "session", tone: "run" } });
    const pill = screen.getByText("session");
    expect(pill).toHaveClass("pill--run");
    expect(pill).not.toHaveClass("pill--status");
  });
});
