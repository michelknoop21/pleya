/**
 * De sporen die de spoorkiezer toont, uit de `Version` van het item.
 *
 * Ondertitels: alleen een extern WebVTT-bestand komt als `<track>` in de
 * speler. Een browser leest geen SRT, ASS of beeldondertitels (PGS, DVD), en
 * ingebedde sporen leveren vraagt extractie op de server. Beide horen bij S13.4
 * (ondertitelconversie naar WebVTT); tot die er is laat de kiezer ze weg en
 * zegt hij hoeveel het er zijn.
 *
 * Het bestand komt via `GET /subtitles/{id}` met de bearer in de header en gaat
 * als `blob:`-URL aan de `<track>`, net als artwork: een `<track src>` kan geen
 * header zetten en een querytoken zou het token in een URL zetten.
 *
 * Audio: het contract heeft geen spoorkeuze in het plan, en de omzetter neemt
 * het eerste audiospoor. Wisselen kan dus alleen bij direct play in een browser
 * met `HTMLMediaElement.audioTracks` (Safari).
 */
import type { AudioStream, SubtitleStream, Version } from '../api/types';
import { formatLanguage } from '../util/format';
import { t } from '../i18n';

export interface TrackOption {
  id: string;
  label: string;
  isDefault: boolean;
}

function label(
  parts: (string | null | undefined)[],
  index: number
): string {
  const text = parts.filter(Boolean).join(' · ');
  return text || t('player.trackUnnamed', { index: index + 1 });
}

export function isBrowserSubtitle(s: SubtitleStream): boolean {
  return s.format === 'vtt' && s.is_external;
}

export function subtitleOptions(version: Version | undefined): {
  usable: TrackOption[];
  skipped: number;
} {
  const all = version?.subtitle_streams ?? [];
  const usable = all.filter(isBrowserSubtitle).map((s, i) => ({
    id: s.id,
    label: label(
      [
        formatLanguage(s.language),
        s.title,
        s.is_forced ? t('item.forced') : null,
        s.is_hearing_impaired ? t('item.sdh') : null
      ],
      i
    ),
    isDefault: s.is_default ?? false
  }));
  return { usable, skipped: all.length - usable.length };
}

export function audioOptions(version: Version | undefined): TrackOption[] {
  return (version?.audio_streams ?? []).map((a: AudioStream, i) => ({
    id: a.id,
    label: label(
      [formatLanguage(a.language), a.title, a.codec, a.channels ? `${a.channels}ch` : null],
      i
    ),
    isDefault: a.is_default ?? false
  }));
}

/** Het audiospoor dat speelt zonder keuze: het standaardspoor, anders het eerste. */
export function defaultAudioIndex(options: TrackOption[]): number {
  const i = options.findIndex((o) => o.isDefault);
  return i >= 0 ? i : 0;
}

/** Laadt een WebVTT-bestand als `blob:`-URL; `revoke` ruimt hem op. */
export async function subtitleBlobUrl(
  text: () => Promise<string>
): Promise<{ url: string; revoke: () => void }> {
  const body = await text();
  const url = URL.createObjectURL(new Blob([body], { type: 'text/vtt' }));
  return { url, revoke: () => URL.revokeObjectURL(url) };
}

/** De tekst van de lopende cues, zonder WebVTT-opmaak (`<i>`, `<c.geel>`, `<v Naam>`). */
export function cueText(cues: ArrayLike<{ text?: string }> | null | undefined): string {
  return Array.from(cues ?? [])
    .map((c) => (c.text ?? '').replace(/<[^>]*>/g, '').trim())
    .filter(Boolean)
    .join('\n');
}
