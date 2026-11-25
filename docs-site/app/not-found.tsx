import type { Metadata } from 'next';
import Link from 'next/link';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { DocsBody, DocsPage, DocsTitle } from 'fumadocs-ui/layouts/docs/page';
import { baseOptions } from '@/lib/layout.shared';
import { source } from '@/lib/source';

export const metadata: Metadata = { title: 'Page not found' };

// Exported to out/404.html; nginx serves it for unknown paths.
export default function NotFound() {
  return (
    <DocsLayout tree={source.getPageTree()} {...baseOptions()}>
      <DocsPage>
        <DocsTitle>Page not found</DocsTitle>
        <DocsBody>
          <p>
            This page doesn&apos;t exist or has moved. Try the search (<kbd>⌘</kbd> <kbd>K</kbd>) or go
            back to the <Link href="/">docs home</Link>.
          </p>
        </DocsBody>
      </DocsPage>
    </DocsLayout>
  );
}
