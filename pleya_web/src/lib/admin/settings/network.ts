/**
 * De gegevens en rekenregels van Netwerk en identiteit (scherm 30).
 *
 * Instelbaar zijn vier sleutels van `PATCH /settings`: `server_name`,
 * `public_url`, `web_origin` en `cors_origins`. Het bindadres, de vertrouwde
 * proxy's, TLS en de poorten horen bij het draaien van de container (het
 * contract zegt het zelf: "geen instelling") en staan hier alleen-lezen met de
 * naam van hun variabele. Wat de northstar verder tekent en het contract niet
 * levert: via welke proxy de aanvraag kwam ("Cloudflare-tunnel"), en de regel
 * over TLS. De server meldt alleen of déze aanvraag via een vertrouwde proxy
 * binnenkwam (`behind_proxy`).
 */
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { PleyaClient } from '../../api/client';
import type { ServerDetail, Settings, SettingsPatch } from '../../api/types';
import { t } from '../../i18n';
import {
  CORS_MAX,
  SERVER_NAME_MAX,
  isOrigin,
  isPublicUrl,
  parseList,
  sameList
} from './settings';

/** Een voorbeeldadres voor de invulvelden; het is nergens een standaardwaarde. */
export const EXAMPLE_ADDRESS = 'https://pleya.example.org';
export const ENV_LISTEN = 'PLEYA_SERVER_HTTP_ADDR';
export const ENV_TRUSTED_PROXIES = 'PLEYA_SERVER_TRUSTED_PROXIES';

export interface NetworkData {
  settings: Settings;
  server: ServerDetail;
}

export async function loadNetwork(
  client: PleyaClient,
  settingsApi: AdminSettingsApi,
  signal?: AbortSignal
): Promise<NetworkData> {
  const [settings, server] = await Promise.all([settingsApi.settings(signal), client.server(signal)]);
  return { settings, server };
}

export interface NetworkDraft {
  name: string;
  publicUrl: string;
  webOrigin: string;
  /** Eén origin per regel. */
  cors: string;
}

export function draftFrom(settings: Settings): NetworkDraft {
  return {
    name: settings.server_name.value,
    publicUrl: settings.public_url.value,
    webOrigin: settings.web_origin.value,
    cors: settings.cors_origins.value.join('\n')
  };
}

export interface NetworkErrors {
  name?: string;
  publicUrl?: string;
  webOrigin?: string;
  cors?: string;
}

/** Wat de server ook toetst, vooraf gemeld zodat Opslaan niet eens aan hoeft. */
export function validate(draft: NetworkDraft): NetworkErrors {
  const errors: NetworkErrors = {};
  const name = draft.name.trim();
  if (name === '' || name.length > SERVER_NAME_MAX) {
    errors.name = t('admin.net.err.name', { max: SERVER_NAME_MAX });
  }
  const publicUrl = draft.publicUrl.trim();
  if (publicUrl !== '' && !isPublicUrl(publicUrl)) errors.publicUrl = t('admin.net.err.publicUrl');
  const origin = draft.webOrigin.trim();
  if (origin !== '' && !isOrigin(origin)) errors.webOrigin = t('admin.net.err.origin');
  const list = parseList(draft.cors);
  if (list.length > CORS_MAX) errors.cors = t('admin.net.err.corsMax', { max: CORS_MAX });
  else if (list.includes('*')) errors.cors = t('admin.net.err.corsWildcard');
  else if (list.some((entry) => !isOrigin(entry))) errors.cors = t('admin.net.err.origin');
  return errors;
}

export function networkPatch(settings: Settings, draft: NetworkDraft): SettingsPatch {
  const patch: SettingsPatch = {};
  const name = draft.name.trim();
  if (name !== settings.server_name.value) patch.server_name = name;
  const publicUrl = draft.publicUrl.trim();
  if (publicUrl !== settings.public_url.value) patch.public_url = publicUrl;
  const origin = draft.webOrigin.trim();
  if (origin !== settings.web_origin.value) patch.web_origin = origin;
  const cors = parseList(draft.cors);
  if (!sameList(cors, settings.cors_origins.value)) patch.cors_origins = cors;
  return patch;
}
