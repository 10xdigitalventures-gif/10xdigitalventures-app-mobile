// Centralized theme tokens. Import { colors } from '@/lib/theme'.
// WhatsApp-inspired green accent on dark background.

export const colors = {
  // Backgrounds (dark mode default)
  bg:          '#0b141a',   // main app bg
  bgSurface:   '#111b21',   // headers, tab bar
  bgRaised:    '#1f2c33',   // cards, inputs
  bgDivider:   '#2a3942',

  // Brand accent (WhatsApp greens)
  brand:       '#1db791',   // primary
  brandDark:   '#17a884',
  brandLight:  '#25d366',   // WhatsApp signature
  brandFaint:  '#1db79122',

  // Bubble colors (WhatsApp Web dark)
  bubbleSent:     '#005c4b', // your messages (right)
  bubbleReceived: '#202c33', // their messages (left)

  // Text
  textPrimary:    '#e9edef',
  textSecondary:  '#8696a0',
  textTertiary:   '#667781',
  textOnBrand:    '#06291f',
  textInverted:   '#0b141a',

  // Status
  online:    '#1db791',
  away:      '#ffa726',
  danger:    '#f15c6d',
  dangerDark:'#e04658',
  read:      '#53bdeb',   // blue ticks
  pending:   '#8696a0',   // gray ticks

  // Misc
  white:     '#ffffff',
  black:     '#000000',
  overlay:   'rgba(0,0,0,0.85)',
  ripple:    'rgba(255,255,255,0.08)',
}

export const radius = { sm: 6, md: 10, lg: 14, xl: 20, pill: 999 }
export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 }
export const fontSize = { xs: 11, sm: 13, md: 15, lg: 17, xl: 20, xxl: 24 }