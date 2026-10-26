/**
 * Wire-typen van het afspeelpad (S13.2, S18.3), als aliassen op het
 * gegenereerde contract. Een eigen bestand naast `api/types.ts`, zodat de
 * speler die gedeelde lijst niet laat groeien terwijl beheer er ook aan werkt.
 */
import type { components } from '../api/schema';

type S = components['schemas'];

export type DeviceCapabilities = S['DeviceCapabilities'];
export type CapabilityStrings = S['CapabilityStrings'];
export type PlaybackPlan = S['PlaybackPlan'];
export type PlaybackPlanRequest = S['PlaybackPlanRequest'];
export type PlaybackReason = S['PlaybackReason'];
export type StreamSession = S['StreamSession'];
export type StreamToken = S['StreamToken'];
