import { CREAM, DER, DIE, Figure, GOLD, GROUND, Ground, Phone } from './shared';

/** Sync: each phone writes its own card into a shared folder and reads the other's back. */
export function SyncIllustration() {
  return (
    <Figure
      id="dk-sync"
      title="Two phones each put their own card into a shared folder above them and read the other's card back"
      caption={
        <>
          Each phone writes its own, none overwrite —
          <br />
          merge them all, and the counts come out right.
        </>
      }
      css={`
        .dk-sync-up { stroke-dasharray: 2 10; animation: dk-sync-up 1.8s linear infinite; }
        .dk-sync-down { stroke-dasharray: 2 10; animation: dk-sync-down 1.8s linear infinite; }
        .dk-sync-card { transform-box: fill-box; transform-origin: center; animation: dk-sync-bob 4s ease-in-out infinite; }
        @keyframes dk-sync-up { to { stroke-dashoffset: -24; } }
        @keyframes dk-sync-down { to { stroke-dashoffset: 24; } }
        @keyframes dk-sync-bob { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-5px); } }
        @media (prefers-reduced-motion: reduce) { .dk-sync-up, .dk-sync-down, .dk-sync-card { animation: none; } }
      `}
    >
      {/* The shared folder (the learner's own Drive app folder) */}
      <path d="M232 40 h52 l12 12 h112 a10 10 0 0 1 10 10 v58 a10 10 0 0 1 -10 10 H232 a10 10 0 0 1 -10 -10 V50 a10 10 0 0 1 10 -10 z" fill={GOLD} />
      {/* One file per phone inside it */}
      <g className="dk-sync-card">
        <rect x={250} y={66} width={60} height={44} rx={5} fill={CREAM} stroke={DER} strokeWidth={4} />
      </g>
      <g className="dk-sync-card" style={{ animationDelay: '2s' }}>
        <rect x={330} y={66} width={60} height={44} rx={5} fill={CREAM} stroke={DIE} strokeWidth={4} />
      </g>
      {/* Each phone writes its own (solid colour up) and reads both (cream down) */}
      <path className="dk-sync-up" d="M130 118 C 150 90, 200 90, 248 90" fill="none" stroke={DER} strokeWidth={3.5} strokeLinecap="round" />
      <path className="dk-sync-down" d="M150 132 C 190 132, 250 128, 300 116" fill="none" stroke={GROUND} strokeWidth={3} strokeLinecap="round" />
      <path className="dk-sync-up" d="M510 118 C 490 90, 440 90, 392 90" fill="none" stroke={DIE} strokeWidth={3.5} strokeLinecap="round" />
      <path className="dk-sync-down" d="M490 132 C 450 132, 390 128, 340 116" fill="none" stroke={GROUND} strokeWidth={3} strokeLinecap="round" />
      <Phone x={120} y={176} button={DER} />
      <Phone x={520} y={176} button={DIE} />
      <Ground />
    </Figure>
  );
}
