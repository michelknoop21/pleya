/**
 * De rolgate van `/admin` (S10.7).
 *
 * Een lid krijgt op elk beheerpad dezelfde 404 als op een pad dat niet bestaat,
 * en de beheerlaag rendert dan niet: er gaat geen enkele beheeraanvraag de deur
 * uit. Een bezoeker zonder sessie krijgt geen 404 maar volgt het gewone pad
 * naar inloggen of setup; dat regelt de schil. Een onbereikbare server laat de
 * rol open, en dan tekent de schil de onbereikbare staat in plaats van de
 * route. Komt de server terug met een lid, dan vangt `routes/admin/+layout`
 * dat op.
 *
 * De tekst is die van de router zelf ("Not Found"), zodat een lid aan de
 * pagina niet kan zien dat het pad wel bestaat.
 *
 * Dit is netheid en geen beveiliging: de bundel is statisch en de server
 * weigert een lid zelf met 404.
 */
import { error } from '@sveltejs/kit';

import type { SessionState } from '../stores/session.svelte';

export type GateSession = Pick<SessionState, 'ensureStarted' | 'phase' | 'canAdminister'>;

export async function adminGate(session: GateSession): Promise<void> {
  await session.ensureStarted();
  if (session.phase === 'ready' && !session.canAdminister) error(404, 'Not Found');
}
