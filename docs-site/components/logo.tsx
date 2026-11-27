import type { SVGProps } from 'react';

/** Die Kartei mark: the card box from the app icon, drawn as a line icon. */
export function KarteiLogo(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 64 64" role="img" aria-label="Die Kartei" fill="none" {...props}>
      <g stroke="currentColor" strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M22 6h20M19 12h26" />
        <rect x="16" y="17" width="32" height="25" rx="5" />
        <path d="M10 40l4-5h36l4 5v13a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4z" />
        <path d="M10 40h14a8 6 0 0 0 16 0h14" />
      </g>
    </svg>
  );
}
