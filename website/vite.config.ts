import { enhancedImages } from "@sveltejs/enhanced-img";
import { sveltekit } from "@sveltejs/kit/vite";
import Icons from "unplugin-icons/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [enhancedImages(), sveltekit(), Icons({ compiler: "svelte" })],
  preview: { allowedHosts: ["*"] },
  // /releases reads docs/RELEASES.md from the repo root, one level above the
  // Vite root. Without this, `vite dev` refuses to serve it.
  server: { fs: { allow: [".."] } },
});
