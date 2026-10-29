/** Browser track labels and bounded SRT/WebVTT delivery through the existing authenticated route. */
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

export function isBrowserSubtitle(s: SubtitleStream, embedded = false): boolean {
  return (s.format === 'vtt' || s.format === 'srt') && (s.is_external || embedded);
}

export function subtitleOptions(version: Version | undefined, embedded = false): {
  usable: TrackOption[];
  skipped: number;
} {
  const all = version?.subtitle_streams ?? [];
  const usable = all.filter((stream) => isBrowserSubtitle(stream, embedded)).map((s, i) => ({
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
  text: () => Promise<string>, format = 'vtt'
): Promise<{ url: string; revoke: () => void }> {
  const body = subtitleWebVtt(await text(), format);
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

/** Converts bounded plain text; ASS/bitmap styling requires the server burn path. */
export function subtitleWebVtt(source: string, format: string): string {
  if (source.length > 4 * 1024 * 1024 || new TextEncoder().encode(source).length > 4 * 1024 * 1024) throw new Error('Subtitle too large');
  const body = source.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  if (format === 'vtt') {
    if (!/^WEBVTT(?:[ \t][^\n]*)?(?:\n|$)/.test(body)) throw new Error('Invalid WebVTT');
    return body;
  }
  if (format !== 'srt') throw new Error('Unsupported subtitle format');
  if (!body.trim()) throw new Error('Invalid SRT');
  const cues = body.trim().split(/\n[ \t]*\n+/).map(block => {
    const lines = block.split('\n');
    const identifier = /^\d+$/.test(lines[0]?.trim() ?? '') ? lines.shift()!.trim() : null;
    const timing = lines.shift()?.match(/^(\d{2,}:[0-5]\d:[0-5]\d[,.]\d{3})[ \t]+-->[ \t]+(\d{2,}:[0-5]\d:[0-5]\d[,.]\d{3})[ \t]*$/);
    if (!timing || lines.length === 0) throw new Error('Invalid SRT');
    const start = subtitleTime(timing[1]!);
    const end = subtitleTime(timing[2]!);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || end <= start) throw new Error('Invalid SRT');
    return `${identifier === null ? '' : identifier + '\n'}${timing[1]!.replace(',', '.')} --> ${timing[2]!.replace(',', '.')}\n${lines.join('\n')}`;
  });
  return `WEBVTT\n\n${cues.join('\n\n')}\n`;
}

function subtitleTime(stamp: string): number {
  const [hours, minutes, seconds, milliseconds] = stamp.split(/[:,.]/).map(Number);
  return ((hours! * 60 + minutes!) * 60 + seconds!) * 1000 + milliseconds!;
}
