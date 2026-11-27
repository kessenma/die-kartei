import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  // Fully static site: `next build` writes plain HTML/JS/CSS to `out/`,
  // which nginx serves (see Dockerfile). No Node server at runtime.
  output: 'export',
  // `/self-hosting/install-docker/` -> `out/self-hosting/install-docker/index.html`
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default withMDX(config);
