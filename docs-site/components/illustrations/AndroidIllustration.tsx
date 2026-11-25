import { ALUMINIUM, CREAM, DAS, DER, DIE, Figure, GOLD, GROUND, Ground, Phone } from './shared';

/** Android: one shared core of the app's own code feeding two phones. */
export function AndroidIllustration() {
  return (
    <Figure
      id="dk-android"
      title="One shared block of code in the middle sends the same cards to two phones"
      caption={
        <>
          One core of Swift, two phones to fill —
          <br />
          the same words, the same drill.
        </>
      }
      css={`
        .dk-android-flow { stroke-dasharray: 2 10; animation: dk-android-flow 1.8s linear infinite; }
        .dk-android-core { transform-box: fill-box; transform-origin: center; animation: dk-android-breathe 4.4s ease-in-out infinite; }
        @keyframes dk-android-flow { to { stroke-dashoffset: -24; } }
        @keyframes dk-android-breathe { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.05); } }
        @media (prefers-reduced-motion: reduce) { .dk-android-flow, .dk-android-core { animation: none; } }
      `}
    >
      {/* The shared core: a stack of the four colours */}
      <g className="dk-android-core">
        <rect x={262} y={70} width={116} height={120} rx={14} fill={ALUMINIUM} stroke={GROUND} strokeWidth={3} />
        <rect x={280} y={88} width={80} height={16} rx={4} fill={DER} />
        <rect x={280} y={110} width={80} height={16} rx={4} fill={DIE} />
        <rect x={280} y={132} width={80} height={16} rx={4} fill={DAS} />
        <rect x={280} y={154} width={80} height={16} rx={4} fill={GOLD} />
      </g>
      {/* To each phone */}
      <path className="dk-android-flow" d="M262 130 H160" fill="none" stroke={GOLD} strokeWidth={3.5} strokeLinecap="round" />
      <path className="dk-android-flow" d="M378 130 H480" fill="none" stroke={GOLD} strokeWidth={3.5} strokeLinecap="round" />
      <Phone x={120} y={170} button={DER} />
      <Phone x={520} y={170} button={DAS} />
      {/* The same card on both screens */}
      <rect x={102} y={146} width={36} height={22} rx={3} fill={CREAM} />
      <rect x={502} y={146} width={36} height={22} rx={3} fill={CREAM} />
      <Ground />
    </Figure>
  );
}
