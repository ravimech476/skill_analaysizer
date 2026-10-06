/**
 * One identity colour per module, used by the sidebar icon and by that module's
 * dashboard tile so the two always agree.
 *
 * These are assigned by hand rather than hashed: a hash clustered four teal items
 * into one group, which reads as a mistake. Within every sidebar group the colours
 * are all different, so neighbouring rows never repeat.
 *
 * Each hue has two variants — `dark` for the slate sidebar, `light` for white cards —
 * drawn from the chart palette, already checked for colour-blind separation.
 */
export type ModuleHue = 'teal' | 'blue' | 'violet' | 'amber' | 'rose' | 'green';

export const HUES: Record<ModuleHue, { dark: string; light: string }> = {
  teal: { dark: '#2dd4bf', light: '#0d9488' },
  blue: { dark: '#38bdf8', light: '#0369a1' },
  violet: { dark: '#a78bfa', light: '#6d28d9' },
  amber: { dark: '#fbbf24', light: '#b45309' },
  rose: { dark: '#fb7185', light: '#be123c' },
  green: { dark: '#4ade80', light: '#15803d' },
};

const MODULE_HUE: Record<string, ModuleHue> = {
  // Overview
  dashboard: 'teal',
  reports: 'blue',
  // Academics
  classes: 'blue',
  marks: 'violet',
  documents: 'amber',
  yearend: 'rose',
  // People
  students: 'violet',
  staff: 'rose',
  users: 'blue',
  roles: 'amber',
  // Placement
  skills: 'amber',
  careers: 'violet',
  placement: 'green',
  analyzer: 'blue',
  // Setup & tools
  academic: 'green',
  bulk: 'teal',
  notifications: 'rose',
};

/** The module's colour, as a CSS value. Anything unmapped falls back to teal. */
export const moduleColor = (key: string, on: 'dark' | 'light') => HUES[MODULE_HUE[key] ?? 'teal'][on];
