import { ALUMINIUM, CREAM, DAS, DER, DIE, Figure, GOLD, GROUND, Ground, Phone } from './shared';

/** Build and run: the Mac builds, a dashed line carries it to the emulator, a check comes back. */
export function BuildIllustration() {
  return (
    <Figure
      id="dk-build"
      title="A Mac mini builds the app and sends it to a phone emulator, which shows a card and a green check"
      css={`
        .dk-build-flow { stroke-dasharray: 2 10; animation: dk-build-flow 1.6s linear infinite; }
        .dk-build-led { animation: dk-build-pulse 2.4s ease-in-out infinite; }
        .dk-build-check { transform-box: fill-box; transform-origin: center; animation: dk-build-pop 3.2s ease-in-out infinite; }
        @keyframes dk-build-flow { to { stroke-dashoffset: -24; } }
        @keyframes dk-build-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }
        @keyframes dk-build-pop { 0%, 30% { transform: scale(0.6); } 50%, 100% { transform: scale(1); } }
        @media (prefers-reduced-motion: reduce) { .dk-build-flow, .dk-build-led, .dk-build-check { animation: none; } }
      `}
    >
      {/* Mac mini */}
      <rect x={90} y={176} width={150} height={56} rx={12} fill={ALUMINIUM} stroke={GROUND} strokeWidth={2} />
      <rect x={102} y={182} width={126} height={3} rx={1.5} fill="rgba(255,255,255,0.7)" />
      <circle className="dk-build-led" cx={222} cy={216} r={3.5} fill={GOLD} />
      {/* Source going in: three coloured lines above it */}
      <rect x={110} y={118} width={70} height={9} rx={4.5} fill={DER} />
      <rect x={110} y={134} width={100} height={9} rx={4.5} fill={DIE} />
      <rect x={110} y={150} width={56} height={9} rx={4.5} fill={GOLD} />
      {/* Out to the emulator */}
      <path className="dk-build-flow" d="M240 200 C 320 200, 360 150, 432 150" fill="none" stroke={GOLD} strokeWidth={3.5} strokeLinecap="round" />
      <Phone x={470} y={170} button={DAS} />
      <rect x={452} y={140} width={36} height={22} rx={3} fill={CREAM} />
      {/* The check */}
      <g className="dk-build-check">
        <circle cx={540} cy={92} r={22} fill={DAS} />
        <path d="M529 92 l8 8 l15 -16" fill="none" stroke={CREAM} strokeWidth={4.5} strokeLinecap="round" strokeLinejoin="round" />
      </g>
      <Ground />
    </Figure>
  );
}
