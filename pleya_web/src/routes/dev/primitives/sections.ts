/**
 * De secties van de galerij, in de volgorde waarin ze op de pagina staan. De
 * index links leest deze lijst, en scripts/primitives-shots.ts ook: het id is
 * het anker waarop hij knipt en de naam van de opname in docs/qa/s7-primitives,
 * dus een id hernoemen breekt de vergelijking met eerdere rondes.
 *
 * Gewone Nederlandse labels: de route bestaat alleen in ontwikkeling.
 */
export interface GallerySectionInfo {
  id: string;
  title: string;
}

export const SECTIONS: readonly GallerySectionInfo[] = [
  { id: 'overzicht', title: 'Overzicht' },
  { id: 'velden', title: 'Velden' },
  { id: 'panelen', title: 'Panelen en tegels' },
  { id: 'pillen', title: 'Statuspillen' },
  { id: 'meldingen', title: 'Meldingen' },
  { id: 'chips', title: 'Chips' },
  { id: 'opslagmeter', title: 'Opslagmeter' },
  { id: 'tabel', title: 'Tabel' },
  { id: 'stappen', title: 'Stappen' },
  { id: 'dialoog', title: 'Bevestigdialoog' },
  { id: 'skelet', title: 'Skelet' },
  { id: 'kaarten', title: 'Kaarten' },
  { id: 'hero', title: 'Hero' },
  { id: 'rail', title: 'Rail' }
];

