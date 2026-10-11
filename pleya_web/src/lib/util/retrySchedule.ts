/**
 * Hoe lang de onbereikbare staat wacht voor de volgende poging, in seconden.
 *
 * Eerst snel, want een korte hapering is het vaakst; daarna elke 30 s, zonder
 * bovengrens in aantal. Een herstartende NAS is na een paar minuten terug en
 * dan hoort de app er vanzelf weer te zijn. `attempt` telt vanaf 0: de eerste
 * automatische poging komt na 2 s.
 */
const RAMP = [2, 4, 8, 16] as const;
const STEADY = 30;

export function retryDelay(attempt: number): number {
  return RAMP[attempt] ?? STEADY;
}
