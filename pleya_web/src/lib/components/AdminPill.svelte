<!--
  De Beheer-pil (web.css `.topnav .item.admin`, reviewronde C.5 punt 5): amber
  tekst met tandwiel, ambergevuld zodra je in beheer bent. Alleen getekend voor
  een eigenaar of beheerder; de schil beslist dat met `session.canAdminister`.
  `compact` is de maat voor de mobiele kop: 36 hoog met een raakvlak van 44.
-->
<script lang="ts">
  import AdminIcon from './AdminIcon.svelte';
  import { ADMIN_ROOT } from '../admin/sections';
  import { t } from '../i18n';

  interface Props {
    active?: boolean;
    compact?: boolean;
  }

  let { active = false, compact = false }: Props = $props();
</script>

<a
  class="admin-pill"
  class:admin-pill--on={active}
  class:admin-pill--compact={compact}
  href={ADMIN_ROOT}
  aria-current={active ? 'page' : undefined}
>
  <AdminIcon name="gear" size={compact ? 16 : 18} />
  <span>{t('admin.pill')}</span>
</a>

<style>
  .admin-pill {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    height: 40px;
    padding: 0 14px;
    border-radius: var(--radius-pill);
    font-size: 16px;
    font-weight: 500;
    color: var(--warn-ink);
    white-space: nowrap;
  }

  .admin-pill--on {
    background: var(--amber);
    color: var(--on-amber);
  }

  .admin-pill--compact {
    height: 36px;
    padding: 0 12px;
    gap: 6px;
    font-size: 14px;
  }

  /* 36 hoog is te klein om op te tikken; een onzichtbare laag maakt er 44 van. */
  .admin-pill--compact::before {
    content: '';
    position: absolute;
    inset: -4px 0;
  }

  @media (hover: hover) {
    .admin-pill:not(.admin-pill--on):hover {
      background: var(--fill);
    }
  }

  @media (max-width: 1199px) {
    .admin-pill:not(.admin-pill--compact) {
      padding: 0 12px;
      font-size: 15px;
    }
  }
</style>
