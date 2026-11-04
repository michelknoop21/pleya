/**
 * Wat deze browser werkelijk kan afspelen, als `DeviceCapabilities` voor
 * `POST /playback/plan` (architectuur 9.1, S17).
 *
 * Elke waarde komt uit een vraag aan de browser zelf: `canPlayType` op een
 * `<video>` en, waar MediaSource bestaat, `isTypeSupported`. Niets wordt uit
 * de user-agent afgeleid. Een laag die de browser niet kan beantwoorden blijft
 * weg; een ontbrekend veld is voor de server `unknown` en keurt niets af.
 *
 * Bewust niet gemeld:
 * - `decoder.video_profiles`: een browser zegt per codecstring ja of nee, niet
 *   welke profielnaam (`Main 10`, `High`) hij aankan in de vorm die de server
 *   vergelijkt. Een gok zou een afspeelbaar bestand laten omzetten.
 * - `audio.max_channels` en `audio.passthrough_codecs`: een browser mixt zelf
 *   terug en kent geen doorgifte naar een receiver.
 * - `connection.*`: de webclient meet geen bandbreedte, en `is_local` valt
 *   vanuit een pagina niet vast te stellen.
 */
import type { CapabilityStrings, DeviceCapabilities } from './types';

/** De drie vragen die de probe stelt, los te vervangen in een test. */
export interface ProbeEnv {
  canPlayType(type: string): string;
  /** `MediaSource.isTypeSupported` of `ManagedMediaSource.isTypeSupported`, of null zonder MSE. */
  mseIsTypeSupported: ((type: string) => boolean) | null;
  matchMedia: ((query: string) => { matches: boolean }) | null;
}

/** Codecnamen zoals ffprobe ze levert en de planner ze vergelijkt. */
const VIDEO_PROBES: Record<string, string[]> = {
  h264: ['video/mp4; codecs="avc1.640028"', 'video/mp4; codecs="avc1.42E01E"'],
  hevc: ['video/mp4; codecs="hvc1.1.6.L120.90"', 'video/mp4; codecs="hev1.1.6.L120.90"'],
  av1: ['video/mp4; codecs="av01.0.08M.08"'],
  vp9: ['video/webm; codecs="vp9"', 'video/mp4; codecs="vp09.00.40.08"'],
  vp8: ['video/webm; codecs="vp8"']
};

const AUDIO_PROBES: Record<string, string[]> = {
  aac: ['audio/mp4; codecs="mp4a.40.2"'],
  mp3: ['audio/mpeg', 'audio/mp4; codecs="mp3"'],
  opus: ['audio/webm; codecs="opus"', 'audio/mp4; codecs="opus"'],
  flac: ['audio/flac', 'audio/mp4; codecs="flac"'],
  vorbis: ['audio/webm; codecs="vorbis"'],
  ac3: ['audio/mp4; codecs="ac-3"'],
  eac3: ['audio/mp4; codecs="ec-3"']
};

/**
 * Containers zoals de scanner ze noemt (`ffprobe/convert.go`). `mkv` staat
 * erin omdat een browser hem kan melden; in de praktijk zegt geen enkele
 * gangbare browser ja, en dan remuxt de server naar HLS.
 */
const CONTAINER_PROBES: Record<string, string[]> = {
  mp4: ['video/mp4'],
  mov: ['video/quicktime'],
  webm: ['video/webm'],
  mkv: ['video/x-matroska', 'video/matroska'],
  ogv: ['video/ogg']
};

/** Tien bits in een van de drie codecs die het in een browser kunnen dragen. */
const TEN_BIT_PROBES = [
  'video/mp4; codecs="hvc1.2.4.L120.90"',
  'video/mp4; codecs="av01.0.08M.10"',
  'video/mp4; codecs="vp09.02.40.10"'
];

/**
 * Een codecstring telt als `probably`, of als `maybe` die MediaSource
 * bevestigt. Zonder MediaSource blijft `maybe` staan: dan is direct play de
 * enige weg en beslist het `<video>`-element zelf.
 */
function codecSupported(env: ProbeEnv, type: string): boolean {
  const answer = env.canPlayType(type);
  if (answer === 'probably') return true;
  if (answer !== 'maybe') return false;
  return env.mseIsTypeSupported ? env.mseIsTypeSupported(type) : true;
}

/** Een container zonder codec krijgt hooguit `maybe`; dat is hier al een ja. */
function containerSupported(env: ProbeEnv, type: string): boolean {
  return env.canPlayType(type) !== '';
}

function pick(
  table: Record<string, string[]>,
  test: (type: string) => boolean
): CapabilityStrings {
  const value = Object.entries(table)
    .filter(([, types]) => types.some(test))
    .map(([name]) => name);
  return { value, confidence: 'detected' };
}

/**
 * HDR is een eigenschap van het scherm, niet van de decoder. De server telt
 * hem alleen bij `detected`, dus zonder `matchMedia` blijft het veld weg.
 * Dolby Vision meldt de webclient nooit: geen browser speelt profiel 5 af.
 */
function hdrTransfers(env: ProbeEnv): CapabilityStrings | null {
  if (!env.matchMedia) return null;
  const high =
    env.matchMedia('(video-dynamic-range: high)').matches ||
    env.matchMedia('(dynamic-range: high)').matches;
  return { value: high ? ['hdr10', 'hlg'] : [], confidence: 'detected' };
}

export function probeCapabilities(env: ProbeEnv): DeviceCapabilities {
  const tenBit = TEN_BIT_PROBES.some((type) => codecSupported(env, type));
  const caps: DeviceCapabilities = {
    decoder: {
      video_codecs: pick(VIDEO_PROBES, (type) => codecSupported(env, type)),
      audio_codecs: pick(AUDIO_PROBES, (type) => codecSupported(env, type)),
      containers: pick(CONTAINER_PROBES, (type) => containerSupported(env, type)),
      // Eén getal voor alle codecs, zoals het contract het vraagt. Een tien-bits
      // H.264 (Hi10P) speelt geen browser af; die grens kan dit veld niet
      // uitdrukken en blijft een bekende beperking van het contract.
      max_bit_depth: { value: tenBit ? 10 : 8, confidence: 'detected' }
    }
  };
  const hdr = hdrTransfers(env);
  if (hdr) caps.display = { hdr_transfers: hdr };
  return caps;
}

/** Hoe deze browser een HLS-afspeellijst kan openen. */
export interface HlsSupport {
  /** hls.js via MediaSource of ManagedMediaSource. */
  hlsjs: boolean;
  /** De browser speelt `application/vnd.apple.mpegurl` zelf (Safari). */
  native: boolean;
}

/**
 * Dezelfde toets als `Hls.isSupported()` (MediaSource met H.264 en AAC), maar
 * zonder hls.js te laden: een film die direct speelt heeft die bundel niet
 * nodig.
 */
export function hlsSupport(env: ProbeEnv): HlsSupport {
  return {
    hlsjs: env.mseIsTypeSupported?.('video/mp4; codecs="avc1.42E01E,mp4a.40.2"') ?? false,
    native: env.canPlayType('application/vnd.apple.mpegurl') !== ''
  };
}

/** De echte omgeving, met een los `<video>` als vraagbaak. */
export function browserProbeEnv(): ProbeEnv {
  const video = document.createElement('video');
  const g = globalThis as unknown as {
    MediaSource?: { isTypeSupported(t: string): boolean };
    ManagedMediaSource?: { isTypeSupported(t: string): boolean };
  };
  const mse = g.ManagedMediaSource ?? g.MediaSource ?? null;
  return {
    canPlayType: (type) => video.canPlayType(type),
    mseIsTypeSupported: mse ? (type) => mse.isTypeSupported(type) : null,
    matchMedia: typeof matchMedia === 'function' ? (q) => matchMedia(q) : null
  };
}
