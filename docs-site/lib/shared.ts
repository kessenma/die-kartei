import { createGetUrl } from 'fumadocs-core/source';

export const appName = 'Die Kartei Docs';
// Where the site will live once it's deployed (not set up yet).
export const siteUrl = 'https://kessenma.github.io/die-kartei';
export const appUrl = 'https://github.com/kessenma/die-kartei';

export const docsRoute = '/';
export const docsImageRoute = '/og/pages';

export const gitConfig = {
  user: 'kessenma',
  repo: 'die-kartei',
  branch: 'main',
  // MDX lives here relative to the repo root (used for "Edit on GitHub" links)
  contentDir: 'docs-site/content/docs',
};

const getImageUrl = createGetUrl(docsImageRoute);

export function getPageImageUrl(page: { slugs: string[]; locale?: string }) {
  const segments = [...page.slugs, 'image.png'];

  return { segments, url: getImageUrl(segments, page.locale) };
}

/** URL of the raw-markdown copy of a page (served by app/llms.mdx). */
export function getMarkdownUrl(pageUrl: string) {
  const path = pageUrl === '/' ? '/index' : pageUrl.replace(/\/$/, '');
  return `/llms.mdx${path}.md`;
}
