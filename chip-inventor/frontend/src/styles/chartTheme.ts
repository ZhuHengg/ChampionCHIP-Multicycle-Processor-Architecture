// Hex values for SVG/recharts props, which do not resolve CSS variables
// reliably. Keep in sync with the @theme tokens in globals.css.
export const CHART = {
  ink: '#1E1E1E',
  ink2: '#4A4945',
  tick: '#8A877F',
  grid: '#E2DDD1',
  dark: '#2A2A2C',
  accent: '#F2C230',
  ok: '#2E9E48',
  info: '#3B6FD8',
  bad: '#E0484D',
  tooltip: {
    backgroundColor: '#FFFFFF',
    border: '1px solid #ECE8DF',
    borderRadius: 14,
    fontSize: 12,
    boxShadow: '0 12px 30px -18px rgba(60,50,20,0.35)',
  },
} as const;
