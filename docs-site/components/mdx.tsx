import defaultMdxComponents from 'fumadocs-ui/mdx';
import { Step, Steps } from 'fumadocs-ui/components/steps';
import { Tab, Tabs } from 'fumadocs-ui/components/tabs';
import type { MDXComponents } from 'mdx/types';
import { AndroidIllustration } from './illustrations/AndroidIllustration';
import { BuildIllustration } from './illustrations/BuildIllustration';
import { KarteiIllustration } from './illustrations/KarteiIllustration';
import { RoadmapIllustration } from './illustrations/RoadmapIllustration';
import { SyncIllustration } from './illustrations/SyncIllustration';

/**
 * Components available in every MDX page without importing, including one illustration per page.
 * Defaults include Callout, Card/Cards, code blocks (with copy button) and tables.
 */
export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    Step,
    Steps,
    Tab,
    Tabs,
    AndroidIllustration,
    BuildIllustration,
    KarteiIllustration,
    RoadmapIllustration,
    SyncIllustration,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
