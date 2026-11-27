# docs-site: Die Kartei docs

Static docs site for the people building Die Kartei: how the app is put together and the work in
progress (the Android port, sync). Fumadocs on Next.js, exported with `output: 'export'`, served by
nginx. Copied from the Firstline docs (`firstline-emr/apps/docs`), with the PocketDev docs'
illustration style.

## Layout

| Path | What |
| --- | --- |
| `content/docs/**.mdx` | Pages. Frontmatter: `title`, `description` |
| `content/docs/**/meta.json` | Sidebar order; the root uses `---Label---` separators and `...folder` |
| `components/illustrations/` | One Bauhaus picture per page, in the app's gender colours (`shared.tsx`) |
| `components/mdx.tsx` | Components available in MDX without imports (Callout, Steps, Cards, the illustrations) |
| `app/global.css` | Theme: the app icon's blue, Geist, DM Serif headings |
| `lib/shared.ts` | Site name, URL, GitHub repo for "Edit on GitHub" |

## Run

```bash
npm install
npm run dev          # http://localhost:3200
npm run build        # static site in out/
docker build -f docs-site/Dockerfile -t kartei-docs .   # from the repo root
```

## Rules

- **Static only**: every route prerenders; no server features.
- **Internal links end with a slash** (`/android/sync/`), because `trailingSlash: true`.
- **Every page gets one illustration** right after the intro, from `components/illustrations/`,
  with a short rhyming two-line caption. Prefix its CSS classes `dk-<page>-` (the styles are
  global) and give it a reduced-motion off switch.
- **Voice**: short and humble. No hype, no dates on plans, no "beta" or "free for now".
- Describe what's built as built and what's planned as planned; say what's not done.
- The developer notes in `../docs/*.md` stay the source of truth for each subsystem; pages here
  summarise and link to them rather than copying them.
