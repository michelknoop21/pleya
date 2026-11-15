/**
 * Metadata verversen voor één titel (`POST /items/{id}/refresh-metadata`),
 * gedeeld door het menu op het filmdetail en de seriepagina. Het antwoord is
 * de melding voor de beheerder: hoeveel items aan de beurt staan, of waarom de
 * titel niet meedoet.
 */
import { adminApi } from '../api/admin';
import { describeError } from '../api/errors';
import { plural, t } from '../i18n';
import { session } from '../stores/session.svelte.js';

export const canRefreshMetadata = (): boolean =>
  session.canAdminister && session.capabilities?.item_metadata_refresh === true;

export async function refreshMetadata(itemId: string): Promise<string> {
  try {
    const { items } = await adminApi(session.client).refreshItemMetadata(itemId);
    return items > 0 ? plural('detail.refreshMetadataQueued', items) : t('detail.refreshMetadataNone');
  } catch (err) {
    return describeError(err);
  }
}
