import { ALUMINIUM, CREAM, DAS, DER, DIE, Figure, GOLD, GROUND, Ground } from './shared';

/** Roadmap: five coloured steps, a marker walking up them one at a time. */
export function RoadmapIllustration() {
  const steps = [DER, DIE, DAS, GOLD, ALUMINIUM];
  return (
    <Figure
      id="dk-roadmap"
      title="Five steps in the app's colours, climbing to the right, with a marker moving up them"
      css={`
        .dk-roadmap-walker { animation: dk-roadmap-walk 10s steps(1, end) infinite; }
        @keyframes dk-roadmap-walk {
          0% { transform: translate(0, 0); }
          20% { transform: translate(84px, -32px); }
          40% { transform: translate(168px, -64px); }
          60% { transform: translate(252px, -96px); }
          80% { transform: translate(336px, -128px); }
        }
        @media (prefers-reduced-motion: reduce) { .dk-roadmap-walker { animation: none; } }
      `}
    >
      {steps.map((color, i) => (
        <rect
          key={i}
          x={110 + i * 84}
          y={204 - i * 32}
          width={84}
          height={32 + i * 32}
          fill={color}
          stroke={GROUND}
          strokeWidth={2}
        />
      ))}
      {/* The marker: a small cream card standing on the current step */}
      <g className="dk-roadmap-walker">
        <rect x={136} y={172} width={30} height={30} rx={4} fill={CREAM} stroke={GROUND} strokeWidth={2} />
      </g>
      <Ground />
    </Figure>
  );
}
