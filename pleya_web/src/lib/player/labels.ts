/**
 * De chip rechtsboven in mockup 50 ("Direct play · HEVC 4K"): hoe er
 * geleverd wordt, plus de bron als het beeld ongewijzigd doorkomt. Bij een
 * omzetting staat er alleen de wijze; het doelformaat noemt het plan niet.
 */
import type { Version } from '../api/types';
import { t } from '../i18n';
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
