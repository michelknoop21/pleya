/**
 * De geplande taken van Activiteit: per bibliotheek de scanronde die de server
 * zelf inplant.
 *
 * Bron: `GET /libraries` (`scan_interval_seconds`, `scan_on_start`), de laatste
 * scan per bibliotheek uit `GET /scans` en de mounts uit `GET /storage/roots`.
 * Het schema wijzigen gaat via de bibliotheek zelf (`PATCH /libraries/{id}`).
 *
 * Het tijdstip van de volgende ronde komt uit `Library.next_scan_at`, alleen
 * onder `capabilities.scan_schedule`. Wat het contract niet draagt staat er
 * niet: een schema voor de metadataronde, de back-up, de hersteltest en het opruimen. Daar is
 * geen route voor; `GET /jobs` toont alleen taken die al in de wachtrij staan.
 */
import type { Library } from '../api/types';
import type { PillTone } from '../components/StatusPill.svelte';
import { t } from '../i18n';
import type { ActivityData } from './activity';
import { formatDayClock } from '../util/format';
import { intervalLabel, rootsOf, scanActive, scanSummary } from './libraries';

export interface ScheduledRow {
  library: Library;
  title: string;
  detail: string;
  schedule: string;
  last: string;
  lastTone: PillTone;
  /**
   * De volgende geplande ronde. Undefined: de server kent `scan_schedule` niet
   * en de kolom staat er niet. Null: niets gepland (interval 0, of de planner
   * zag de bibliotheek nog niet).
   */
  next?: string | null;
  /** Nu starten kan niet als er al een ronde wacht of loopt, of een root niet gemount is. */
  canRun: boolean;
}

export function scheduledRows(data: ActivityData, now = Date.now(), withNext = false): ScheduledRow[] {
  return data.libraries.map((library) => {
    const scan = data.lastScans[library.id] ?? null;
    const unmounted = rootsOf(data.roots, library.id).some((r) => !r.mounted);
    const interval =
      typeof library.scan_interval_seconds === 'number'
        ? intervalLabel(library.scan_interval_seconds)
        : t('admin.lib.interval.default');
    const summary = scanSummary(scan, now);
    return {
      library,
      title: t('admin.act.history.scan', { library: library.title }),
      detail: t(unmounted ? 'admin.act.sched.unmounted' : 'admin.act.sched.scanDetail'),
      schedule: library.scan_on_start === false ? interval : t('admin.act.sched.andOnStart', { interval }),
      last: summary.text,
      lastTone: summary.tone,
      ...(withNext ? { next: formatDayClock(library.next_scan_at, now) } : {}),
      canRun: !unmounted && !scanActive(scan)
    };
  });
}
