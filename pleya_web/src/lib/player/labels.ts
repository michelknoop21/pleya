/**
 * De chip rechtsboven in mockup 50 ("Direct play · HEVC 4K"): hoe er
 * geleverd wordt, plus de bron als het beeld ongewijzigd doorkomt. Bij een
 * omzetting staat er alleen de wijze; het doelformaat noemt het plan niet.
 */
import type { Version } from '../api/types';
import { intlLocale, t } from '../i18n';
import type { DeliveryMode } from './delivery';

const CODEC_NAMES: Record<string, string> = {
  h264: 'H.264',
  hevc: 'HEVC',
  h265: 'HEVC',
  av1: 'AV1',
  vp9: 'VP9',
  vp8: 'VP8'
};

export function resolutionClass(height: number | null | undefined): string | null {
  if (!height) return null;
  if (height >= 2000) return '4K';
  if (height >= 1000) return '1080p';
  if (height >= 700) return '720p';
  return `${height}p`;
}

export function deliveryLabel(mode: DeliveryMode, version: Version | undefined): string {
  const name = t(`player.mode.${mode}`);
  if (mode === 'transcode') return name;
  const video = version?.video_streams?.[0];
  if (!video) return name;
  const codec = CODEC_NAMES[video.codec.toLowerCase()] ?? video.codec.toUpperCase();
  return [name, [codec, resolutionClass(video.height)].filter(Boolean).join(' ')].join(' · ');
}

/** "HEVC Main 10 · 3840 × 2160" voor de afspeelinfo; null zonder videospoor. */
export function videoLabel(version: Version | undefined): string | null {
  const video = version?.video_streams?.[0];
  if (!video) return null;
  const codec = CODEC_NAMES[video.codec.toLowerCase()] ?? video.codec.toUpperCase();
  const size = video.width && video.height ? `${video.width} × ${video.height}` : null;
  return [[codec, video.profile].filter(Boolean).join(' '), size].filter(Boolean).join(' · ');
}

export interface QualityOption {
  id: string;
  label: string;
  /** De limiet voor `POST /playback/plan`; null is het origineel. */
  quality: { max_video_bitrate_kbps: number; max_height: number } | null;
}

/** Een keuze uit de tabel van de app (`TranscodeQualityPreset`): hoogte en videobitrate in kbit/s. */
const QUALITY_PRESETS = [[1080, 8000], [720, 4000], [480, 1500]] as const;

/** Origineel plus de limieten onder de bron: de server vergroot een bron niet. */
export function qualityOptions(version: Version | undefined): QualityOption[] {
  const height = version?.video_streams?.[0]?.height ?? 0;
  const mbit = new Intl.NumberFormat(intlLocale(), { maximumFractionDigits: 1 });
  return [
    { id: 'original', label: [t('player.qualityOriginal'), resolutionClass(height)].filter(Boolean).join(' · '), quality: null },
    ...QUALITY_PRESETS.filter(([h]) => !height || h <= height).map(([h, kbps]) => ({
      id: String(h),
      label: `${h}p · ${mbit.format(kbps / 1000)} Mbit/s`,
      quality: { max_video_bitrate_kbps: kbps, max_height: h }
    }))
  ];
}

/** De regels van de afspeelinfo. Alleen wat een bron heeft: het plan, de versie en het `<video>`-element. */
export function playbackInfo(now: {
  mode: DeliveryMode | undefined;
  version: Version | undefined;
  audio: string | undefined;
  subtitle: string | null;
  /** Seconden gebufferd voorbij de afspeelpositie. */
  ahead: number;
  frames: { dropped: number; total: number } | null;
}): [label: string, value: string][] {
  return [
    [t('player.info.method'), now.mode ? t(`player.mode.${now.mode}`) : null],
    [t('item.video'), videoLabel(now.version)],
    [t('item.audio'), now.audio],
    [t('player.subtitles'), now.subtitle ?? t('player.subtitlesOff')],
    [t('player.info.buffer'), t('player.info.bufferValue', { seconds: Math.max(0, Math.round(now.ahead)) })],
    [t('player.info.dropped'), now.frames ? t('player.info.droppedValue', now.frames) : null]
  ].filter((row): row is [string, string] => Boolean(row[1]));
}
