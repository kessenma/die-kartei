/**
 * App screenshots in the docs. Images live in public/screens/ (600px wide JPEGs from the iPhone
 * simulator). Markers are positioned in iPhone points (the screen is 402 × 874), so a marker's
 * x/y can be read straight off `idb ui describe-all` or the accessibility inspector.
 */
import type { ReactNode } from 'react';

const SCREEN_W = 402;
const SCREEN_H = 874;

function Shot({ src, alt, children }: { src: string; alt: string; children?: ReactNode }) {
  return (
    <div className="relative mx-auto w-full max-w-[240px] overflow-hidden rounded-[1.6rem] border-[5px] border-fd-foreground/85 bg-fd-background shadow-lg">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`/screens/${src}.jpg`} alt={alt} loading="lazy" className="m-0 block h-auto w-full" />
      {children}
    </div>
  );
}

/** One screenshot with an optional one-line caption. */
export function Screen({ src, alt, caption }: { src: string; alt: string; caption?: ReactNode }) {
  return (
    <figure className="not-prose my-6">
      <Shot src={src} alt={alt} />
      {caption && <figcaption className="mt-2 text-center text-sm text-fd-muted-foreground">{caption}</figcaption>}
    </figure>
  );
}

/** Two or three screenshots side by side (stacked on narrow screens). */
export function Screens({ children }: { children: ReactNode }) {
  return <div className="not-prose my-6 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 [&>figure]:my-0">{children}</div>;
}

export type Mark = { x: number; y: number; text: ReactNode };

/** A screenshot with numbered markers and the matching numbered notes beside it. */
export function Annotated({ src, alt, marks }: { src: string; alt: string; marks: Mark[] }) {
  return (
    <figure className="not-prose my-6 flex flex-col items-center gap-6 sm:flex-row sm:items-start">
      <div className="w-full sm:w-[240px] sm:shrink-0">
        <Shot src={src} alt={alt}>
          {marks.map((m, i) => (
            <span
              key={i}
              aria-hidden
              className="absolute flex size-6 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-white bg-fd-primary text-xs font-semibold text-white shadow"
              style={{ left: `${(m.x / SCREEN_W) * 100}%`, top: `${(m.y / SCREEN_H) * 100}%` }}
            >
              {i + 1}
            </span>
          ))}
        </Shot>
      </div>
      <ol className="m-0 flex list-none flex-col gap-3 p-0 text-sm sm:pt-4">
        {marks.map((m, i) => (
          <li key={i} className="flex gap-3">
            <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-fd-primary text-xs font-semibold text-white">
              {i + 1}
            </span>
            <span className="pt-0.5">{m.text}</span>
          </li>
        ))}
      </ol>
    </figure>
  );
}
