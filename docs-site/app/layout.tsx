import type { Metadata } from 'next';
import { DM_Serif_Text, Geist, Geist_Mono } from 'next/font/google';
import { Provider } from '@/components/provider';
import { appName, siteUrl } from '@/lib/shared';
import './global.css';

const geistSans = Geist({
  subsets: ['latin'],
  variable: '--font-geist-sans',
});

const geistMono = Geist_Mono({
  subsets: ['latin'],
  variable: '--font-geist-mono',
});

// The display serif the PocketDev and Firstline docs use
const dmSerifText = DM_Serif_Text({
  weight: ['400'],
  subsets: ['latin'],
  variable: '--font-dm-serif-text',
});

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    template: `%s | ${appName}`,
    default: appName,
  },
  description:
    'How Die Kartei is built: the shared Swift core, the Android port and how sync will work there.',
};

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} ${dmSerifText.variable} font-sans`}
      suppressHydrationWarning
    >
      <body className="flex flex-col min-h-screen">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
