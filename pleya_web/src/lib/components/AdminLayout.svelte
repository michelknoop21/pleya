<!--
  De beheerschil (web.css `.admin`): zijbalk links en de inhoud rechts.
  Vanaf 1200 is de zijbalk 232 breed met 40 tussenruimte, van 900 tot 1199
  200 met 28; onder 900 is er geen zijbalk en neemt de mobiele index (33) die
  rol over, met de terugkop in MobileHeader (DESIGN.md hoofdstuk 3).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  import AdminNav from './AdminNav.svelte';
  import type { AdminSectionId } from '../admin/sections';

  interface Props {
    active: AdminSectionId | null;
    children: Snippet;
  }

  let { active, children }: Props = $props();
</script>

<div class="admin">
  <div class="admin__nav">
    <AdminNav {active} />
  </div>
  <div class="admin__main">
    {@render children()}
  </div>
</div>

<style>
  .admin {
    display: grid;
    grid-template-columns: 232px minmax(0, 1fr);
    gap: 40px;
    padding: 8px var(--inset) 40px;
  }

  /* Een gewoon blok dat de grid tot de volle hoogte rekt: de sticky zijbalk
     erin heeft dan ruimte om mee te schuiven. */
  .admin__nav {
    min-width: 0;
  }

  .admin__main {
    min-width: 0;
  }

  @media (max-width: 1199px) {
    .admin {
      grid-template-columns: 200px minmax(0, 1fr);
      gap: 28px;
    }
  }

  @media (max-width: 899px) {
    .admin {
      display: block;
      padding: 8px var(--inset) 24px;
    }

    .admin__nav {
      display: none;
    }
  }
</style>
