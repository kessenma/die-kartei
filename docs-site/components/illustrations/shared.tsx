/**
 * Docs illustrations: one per page, flat Bauhaus shapes in the app's gender colours
 * (GrammarPalette.swift: der blue, die red, das green, plural gold), slow CSS motion with a
 * reduced-motion off switch, and a short rhyming caption. Same family as the PocketDev docs.
 * Class names are prefixed per picture (dk-<page>-*) because the <style> blocks are global.
 */
import type { ReactNode } from 'react';

export const DER = '#2F6BFF';
export const DIE = '#E23D4C';
export const DAS = '#1FA971';
export const GOLD = '#D9930E';
export const INK = '#1a1a1a';
export const CREAM = '#f5f1e4';
export const ALUMINIUM = '#d9d9d6';
export const GROUND = '#7d7468';

export function Figure({
  id,
  title,
  caption,
  viewBox = '0 0 640 260',
  css,
  children,
}: {
  id: string;
  title: string;
  caption: ReactNode;
  viewBox?: string;
  css: string;
  children: ReactNode;
}) {
  return (
    <figure className="not-prose my-8">
      <svg
        viewBox={viewBox}
        role="img"
        aria-labelledby={`${id}-title`}
        className="mx-auto block h-auto w-full max-w-xl"
      >
        <title id={`${id}-title`}>{title}</title>
        <style>{css}</style>
        {children}
      </svg>
      <figcaption className="mt-2 text-center text-sm" style={{ color: '#998d79' }}>
        {caption}
      </figcaption>
    </figure>
  );
}

/** A generic phone: dark body, a screen, a coloured button. */
export function Phone({ x, y, button }: { x: number; y: number; button: string }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x={-30} y={-56} width={60} height={110} rx={12} fill={INK} stroke={GROUND} strokeWidth={2} />
      <rect x={-22} y={-42} width={44} height={86} rx={6} fill="rgba(255,255,255,0.1)" />
      <rect x={-10} y={-51} width={20} height={3} rx={1.5} fill="rgba(255,255,255,0.2)" />
      <rect x={-16} y={18} width={32} height={14} rx={4} fill={button} />
    </g>
  );
}

/** The ground line every picture stands on. */
export function Ground({ y = 236 }: { y?: number }) {
  return <line x1={40} y1={y} x2={600} y2={y} stroke={GROUND} strokeWidth={3} strokeLinecap="round" />;
}
