import { error } from '@sveltejs/kit';
import { dev } from '$app/environment';

/**
 * De primitievengalerij is gereedschap voor ontwikkeling en review, geen
 * scherm. Buiten `vite dev` bestaat hij niet: de bundel serveert elk pad via
 * `index.html`, dus de enige plek om hem dicht te zetten is deze load, die
 * vóór het renderen een 404 gooit.
 */
export function load(): void {
  if (!dev) error(404, 'Not found');
}
