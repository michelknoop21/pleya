<!--
  De kengetallen van scherm 37: nu bezig, het maximum en de hardware. De
  northstar tekent een vierde tegel met de grootte van de transcodemap; de
  server meldt die niet, dus hij staat hier niet.
-->
<script lang="ts">
  import AdminIcon from '../../components/AdminIcon.svelte';
  import StatTile from '../../components/StatTile.svelte';
  import type { TranscodeSessionList } from '../../api/types';
  import { plural, t } from '../../i18n';

  let { list }: { list: TranscodeSessionList } = $props();

  const count = $derived(list.items.length);
  const hardware = $derived(
    list.hardware.accel === 'none' ? t('admin.tc.tile.software') : list.hardware.accel.toUpperCase()
  );
</script>

<div class="tiles">
  <StatTile
    label={t('admin.tc.tile.busy')}
    value={String(count)}
    sub={count === 0 ? t('admin.tc.tile.busyNone') : plural('admin.tc.tile.busySub', count)}
  >
    {#snippet icon()}<AdminIcon name="activity" />{/snippet}
  </StatTile>
  <StatTile
    label={t('admin.tc.tile.max')}
    value={list.max_sessions === 0 ? t('admin.tc.tile.maxOff') : String(list.max_sessions)}
    sub={list.max_sessions === 0 ? t('admin.tc.tile.maxOffSub') : t('admin.tc.tile.maxSub')}
  >
    {#snippet icon()}<AdminIcon name="cpu" />{/snippet}
  </StatTile>
  <StatTile
    label={t('admin.tc.tile.hardware')}
    value={hardware}
    sub={list.hardware.reason ?? t('admin.tc.tile.hardwareSub')}
  >
    {#snippet icon()}<AdminIcon name="tv" />{/snippet}
  </StatTile>
</div>

<style>
  .tiles {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 16px;
  }

  @media (max-width: 899px) {
    .tiles {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }

    /* De derde tegel staat anders alleen op een halve rij. */
    .tiles > :global(:last-child) {
      grid-column: 1 / -1;
    }
  }

  @media (max-width: 359px) {
    .tiles {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
