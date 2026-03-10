// Colour palette metadata for the UI (must stay in sync with shaders.wgsl palette indices).
export interface PaletteInfo {
  name: string;
  /** Representative CSS gradient stops for the swatch preview */
  previewColors: string[];
}

export const PALETTES: PaletteInfo[] = [
  { name: 'Classic',     previewColors: ['#0028c8', '#22aaee', '#ffffff', '#ffaa00', '#000010'] },
  { name: 'Fire',        previewColors: ['#000000', '#990000', '#ff5500', '#ffcc00', '#ffffff'] },
  { name: 'Ocean',       previewColors: ['#001166', '#0044bb', '#00aacc', '#88ddff', '#ffffff'] },
  { name: 'Neon',        previewColors: ['#aa00ff', '#ff0066', '#ffee00', '#00ff88', '#00aaff'] },
  { name: 'Purple Haze', previewColors: ['#000000', '#440066', '#6600cc', '#9966ff', '#ddbbff'] },
  { name: 'Sunset',      previewColors: ['#440011', '#cc2200', '#ff6600', '#ffbb00', '#ff88aa'] },
  { name: 'Ice',         previewColors: ['#3366ff', '#66ccff', '#aaeeff', '#ffffff', '#ddeeff'] },
  { name: 'Forest',      previewColors: ['#000000', '#003300', '#006600', '#44aa00', '#aadd00'] },
];

export interface JuliaPreset {
  name: string;
  cx: number;
  cy: number;
}

export const JULIA_PRESETS: JuliaPreset[] = [
  { name: "Douady's Rabbit", cx: -0.7000, cy:  0.27015 },
  { name: 'Siegel Disk',     cx: -0.3905, cy: -0.58679 },
  { name: 'Spiral',          cx:  0.2850, cy:  0.01000 },
  { name: 'Dendrite',        cx:  0.0000, cy:  1.00000 },
  { name: 'San Marco',       cx: -0.7380, cy:  0.18800 },
  { name: 'Cauliflower',     cx:  0.4500, cy:  0.14280 },
  { name: 'Airplane',        cx: -0.7017, cy: -0.38420 },
  { name: 'Electric',        cx: -0.8350, cy: -0.23210 },
];
