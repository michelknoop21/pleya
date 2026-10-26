/**
 * hls.js aan een `<video>`, met herstel en een nette eindstaat.
 *
 * Configuratie, getoetst aan de documentatie van hls.js 1.7 (Context7,
 * `/video-dev/hls.js`, docs/API.md: xhrSetup, enableWorker, startPosition,
 * recoverMediaError):
 *
 * - `xhrSetup` opent elke aanvraag zelf en zet de bearer in de header. Een
 *   afspeellijst of segment krijgt dus nooit een token in de URL, en een
 *   verlopen accesstoken wordt vóór de aanvraag ververst.
 * - `enableWorker: false`: hls.js zou zijn worker uit een `blob:`-URL starten,
 *   en dat vraagt `worker-src blob:` in de CSP. De segmenten zijn al fMP4, er
 *   valt nauwelijks te transmuxen, dus de hoofdthread volstaat en de CSP blijft
 *   strak.
 * - `startPosition: 0`: de server schrijft een EVENT-afspeellijst die meegroeit
 *   met de omzetting. hls.js ziet die als live en zou standaard bij de rand
 *   beginnen; een film begint bij het begin.
 *
 * Herstel volgt het patroon uit dezelfde documentatie: een fatale netwerkfout
 * krijgt een paar keer `startLoad`, een fatale mediafout eerst
 * `recoverMediaError` en daarna `swapAudioCodec` plus nog een herstel. Wat
 * dan nog faalt wordt een foutcode voor `playerErrors`, en de instantie gaat
 * weg. Een 404 op een sessiebestand betekent dat de sessie op de server weg
 * is: opnieuw laden helpt dan niet.
 */

export interface HlsErrorData {
  type: string;
  details: string;
  fatal: boolean;
  response?: { code: number };
}

/** Het deel van een Hls-instantie dat de speler gebruikt. */
export interface HlsLike {
  loadSource(url: string): void;
  attachMedia(media: HTMLMediaElement): void;
  on(event: string, listener: (event: string, data: HlsErrorData) => void): void;
  startLoad(startPosition?: number): void;
  recoverMediaError(): void;
  swapAudioCodec(): void;
  destroy(): void;
}

export interface HlsCtor {
  new (config: Record<string, unknown>): HlsLike;
  isSupported(): boolean;
  Events: { ERROR: string; FRAG_LOADED: string };
  ErrorTypes: { NETWORK_ERROR: string; MEDIA_ERROR: string };
}

export const MAX_NETWORK_RETRIES = 3;
export const MAX_MEDIA_RECOVERIES = 2;

export interface HlsAttachOptions {
  Hls: HlsCtor;
  media: HTMLMediaElement;
  url: string;
  bearer: () => Promise<string | null>;
  /** Na alle herstelpogingen: een foutcode, daarna is de instantie al weg. */
  onFatal: (code: string) => void;
  /** Wachttijd voor een nieuwe laadpoging; los te vervangen in een test. */
  schedule?: (fn: () => void, ms: number) => void;
}

export interface HlsHandle {
  destroy(): void;
}

export function hlsConfig(bearer: () => Promise<string | null>): Record<string, unknown> {
  return {
    enableWorker: false,
    startPosition: 0,
    lowLatencyMode: false,
    xhrSetup: async (xhr: XMLHttpRequest, url: string) => {
      xhr.open('GET', url, true);
      const token = await bearer();
      if (token) xhr.setRequestHeader('Authorization', `Bearer ${token}`);
    }
  };
}

export function attachHls(options: HlsAttachOptions): HlsHandle {
  const { Hls, media, url, onFatal } = options;
  const schedule = options.schedule ?? ((fn, ms) => void globalThis.setTimeout(fn, ms));
  const hls = new Hls(hlsConfig(options.bearer));
  let networkRetries = 0;
  let mediaRecoveries = 0;
  let destroyed = false;

  const fail = (code: string) => {
    if (destroyed) return;
    destroy();
    onFatal(code);
  };

  function destroy(): void {
    if (destroyed) return;
    destroyed = true;
    hls.destroy();
  }

  hls.on(Hls.Events.FRAG_LOADED, () => {
    networkRetries = 0;
  });

  hls.on(Hls.Events.ERROR, (_event, data) => {
    // Niet-fataal herstelt hls.js zelf; ingrijpen zou dat juist verstoren.
    if (!data.fatal || destroyed) return;

    if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
      const status = data.response?.code ?? 0;
      if (status === 404) return fail('client.session_ended');
      if (status === 401 || status === 403) return fail('auth.token_invalid');
      if (networkRetries >= MAX_NETWORK_RETRIES) return fail('client.media_network');
      networkRetries += 1;
      schedule(() => {
        if (!destroyed) hls.startLoad();
      }, 1000 * networkRetries);
      return;
    }

    if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
      if (mediaRecoveries >= MAX_MEDIA_RECOVERIES) return fail('client.media_decode');
      mediaRecoveries += 1;
      if (mediaRecoveries === 2) hls.swapAudioCodec();
      hls.recoverMediaError();
      return;
    }

    fail('client.media_decode');
  });

  hls.attachMedia(media);
  hls.loadSource(url);
  return { destroy };
}
