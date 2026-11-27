import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { KarteiLogo } from '@/components/logo';
import { gitConfig } from './shared';

/** Header breadcrumb in the PocketDev / Firstline docs style: "[logo] Die Kartei / Docs". */
function NavTitle() {
  return (
    <span className="inline-flex items-center gap-2">
      <KarteiLogo className="size-5 text-fd-primary" />
      <span className="fd-display text-[1.05rem] text-fd-foreground">Die Kartei</span>
      <span className="text-xs text-fd-muted-foreground">/</span>
      <span className="text-sm text-fd-muted-foreground">Docs</span>
    </span>
  );
}

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: <NavTitle />,
      url: '/',
    },
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
