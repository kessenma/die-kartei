import { ALUMINIUM, CREAM, DAS, DER, DIE, Figure, GOLD, GROUND, Ground, INK, Phone } from './shared';

/** Home: the card box from the app icon, with der/die/das/plural cards; one lifts out. */
export function KarteiIllustration() {
  return (
    <Figure
      id="dk-home"
      title="A box of index cards in the four gender colours; one card lifts out and settles back"
      caption={
        <>
          A box of cards, a word on each —
          <br />
          one at a time, and all in reach.
        </>
      }
      css={`
        .dk-home-lift { transform-box: fill-box; transform-origin: center; animation: dk-home-lift 4.8s ease-in-out infinite; }
        @keyframes dk-home-lift { 0%, 100% { transform: translateY(0); } 40%, 60% { transform: translateY(-34px) rotate(-4deg); } }
        @media (prefers-reduced-motion: reduce) { .dk-home-lift { animation: none; } }
      `}
    >
      {/* Cards standing in the box, back to front */}
      <rect x={232} y={58} width={176} height={110} rx={10} fill={GOLD} />
      <rect x={244} y={74} width={176} height={110} rx={10} fill={DAS} />
      <g className="dk-home-lift">
        <rect x={220} y={88} width={176} height={110} rx={10} fill={CREAM} stroke={GROUND} strokeWidth={2} />
        <rect x={244} y={112} width={40} height={10} rx={5} fill={DIE} />
        <rect x={292} y={112} width={80} height={10} rx={5} fill={INK} />
        <rect x={244} y={134} width={110} height={6} rx={3} fill={GROUND} opacity={0.5} />
      </g>
      <rect x={210} y={104} width={176} height={110} rx={10} fill={DER} />
      {/* The box front, with its finger notch */}
      <path d="M180 150 H460 V218 a10 10 0 0 1 -10 10 H190 a10 10 0 0 1 -10 -10 Z" fill={ALUMINIUM} stroke={GROUND} strokeWidth={3} />
      <path d="M290 150 a30 22 0 0 0 60 0" fill={CREAM} stroke={GROUND} strokeWidth={3} />
      <Ground />
      {/* A small phone beside it: the same box, on the go */}
      <Phone x={530} y={180} button={DER} />
    </Figure>
  );
}
