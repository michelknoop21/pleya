/**
 * Gegenereerd artwork voor de galerij: een verloop met een zon en de titel
 * erin, op een canvas getekend en als Blob aan de artwork-loader gegeven.
 * Geen TMDb-materiaal in git en geen server nodig; de kaart doorloopt toch
 * het echte pad van Artwork (laden, object-URL, vrijgeven).
 *
 * Een id is `<sleutel>` voor een poster, `<sleutel>@wide` voor een 16:9-
 * beeld of `<sleutel>@hero` voor een backdrop zonder tekst, want over een
 * hero staat de titel al in de displayletter. Een onbekende sleutel faalt, zodat de galerij ook de staat "laden
 * mislukt" kan tonen. De kleuren volgen specimen v3.
 */
import type { ArtworkLoader } from '$lib/components/artworkLoader';

interface DemoArt {
  title: string;
  /** Boven- en onderkleur van het verloop. */
  top: string;
  bottom: string;
  /** Kleur van de zon; straal 0 betekent geen zon. */
  sun: string;
  sunRadius: number;
  credit: string;
}

const ART: Record<string, DemoArt> = {
  dune2: { title: 'Dune: Part Two', top: '#f2a640', bottom: '#3b1a0d', sun: '#ffd27a', sunRadius: 0.24, credit: 'Denis Villeneuve' },
  dune: { title: 'Dune', top: '#e08a3c', bottom: '#2a140a', sun: '#ffcf8a', sunRadius: 0, credit: 'Part one' },
  inter: { title: 'Interstellar', top: '#20324a', bottom: '#0b1118', sun: '#d9e4f2', sunRadius: 0.14, credit: 'Christopher Nolan' },
  anora: { title: 'Anora', top: '#c2347a', bottom: '#2a0f2a', sun: '#ffb0e0', sunRadius: 0, credit: 'Sean Baker' },
  sev: { title: 'Severance', top: '#4aa6d6', bottom: '#0d2a3a', sun: '#d8f1ff', sunRadius: 0, credit: 'Apple TV+' },
  fallout: { title: 'Fallout', top: '#6b5a3c', bottom: '#121410', sun: '#e8d29a', sunRadius: 0.18, credit: 'S1 · E7' },
  opp: { title: 'Oppenheimer', top: '#e2541c', bottom: '#2a0b05', sun: '#ffc070', sunRadius: 0.16, credit: 'Christopher Nolan' },
  civil: { title: 'Civil War', top: '#3a4630', bottom: '#0d0f0b', sun: '#b9f23a', sunRadius: 0, credit: 'Alex Garland' },
  rotk: { title: 'The Return of the King', top: '#1b2440', bottom: '#120d16', sun: '#f2c26b', sunRadius: 0.14, credit: 'Peter Jackson' }
};

const POSTER = { w: 400, h: 600 };
const WIDE = { w: 712, h: 400 };
const HERO = { w: 1344, h: 576 };

/**
 * Een backdrop voor de hero: het verloop schuin van donker links naar licht
 * rechts en de zon rechts van het midden, zoals hero A en B in specimen v3.
 * Links blijft het donker, daar staat de tekst.
 */
export function drawDemoBackdrop(canvas: HTMLCanvasElement, art: DemoArt): void {
  const { w, h } = HERO;
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const gradient = ctx.createLinearGradient(0, h, w, 0);
  gradient.addColorStop(0, art.bottom);
  gradient.addColorStop(1, art.top);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, w, h);
  if (art.sunRadius > 0) {
    ctx.fillStyle = art.sun;
    ctx.beginPath();
    // Op de hoogte en niet op de diagonaal: een brede backdrop gaf anders
    // een zon die het halve beeld vulde.
    ctx.arc(w * 0.7, h * 0.32, art.sunRadius * h, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** Tekent één beeld. Exporteerbaar voor wie het canvas zelf wil hebben. */
export function drawDemoArt(canvas: HTMLCanvasElement, art: DemoArt, wide: boolean): void {
  const { w, h } = wide ? WIDE : POSTER;
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  // 170 graden zoals het specimen: bijna verticaal, licht naar rechts.
  const gradient = ctx.createLinearGradient(w * 0.42, 0, w * 0.58, h);
  gradient.addColorStop(0, art.top);
  gradient.addColorStop(1, art.bottom);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, w, h);

  if (art.sunRadius > 0) {
    ctx.fillStyle = art.sun;
    ctx.beginPath();
    // De straal is een fractie van de diagonaal, zoals een radial-gradient in CSS.
    const r = art.sunRadius * Math.hypot(w, h) * (wide ? 0.42 : 0.5);
    ctx.arc(w * 0.5, h * 0.32, r, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.fillStyle = '#ffffff';
  ctx.textBaseline = 'alphabetic';
  if (!wide) {
    ctx.textAlign = 'center';
    ctx.globalAlpha = 0.62;
    ctx.font = '500 17px Inter, sans-serif';
    ctx.letterSpacing = '4px';
    ctx.fillText(art.credit.toUpperCase(), w / 2, h * 0.09 + 12);
    ctx.globalAlpha = 1;
  }

  ctx.font = '700 34px Inter, sans-serif';
  ctx.letterSpacing = '3px';
  ctx.shadowColor = 'rgba(0, 0, 0, 0.35)';
  ctx.shadowBlur = 8;
  const title = art.title.toUpperCase();
  if (wide) {
    ctx.textAlign = 'left';
    ctx.fillText(title, w * 0.06, h * 0.86);
  } else {
    ctx.textAlign = 'center';
    ctx.fillText(title, w / 2, h * 0.7, w * 0.88);
  }
}

/** De loader die CardSection en HeroSection in de context zetten. */
export const demoArtworkLoader: ArtworkLoader = async (id) => {
  const [key, variant] = id.split('@');
  const art = key ? ART[key] : undefined;
  if (!art) throw new Error(`geen demo-artwork voor ${id}`);
  // Inter moet geladen zijn, anders tekent het canvas in de systeemletter.
  await document.fonts?.ready;
  const canvas = document.createElement('canvas');
  if (variant === 'hero') drawDemoBackdrop(canvas, art);
  else drawDemoArt(canvas, art, variant === 'wide');
  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('toBlob'))), 'image/png');
  });
};
