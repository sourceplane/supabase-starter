import type { Metadata } from "next";
import { Geist } from "next/font/google";
import { ThemeProvider } from "next-themes";
import "./globals.css";
import { SITE_NAME } from "@/lib/site";

// The product's public origin, which the Open Graph and Twitter images'
// absolute URLs resolve against. Not upstream's: it read VERCEL_URL, which no
// Cloudflare build has, so every deployed page pointed its images at
// localhost. Baked in at build — component.yaml's buildCommand sets it from
// the environment's SITE_URL (a custom domain), else its workers.dev URL, the
// same origin the Supabase project's Auth sends its links to.
const defaultUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(defaultUrl),
  title: SITE_NAME,
  description: "The fastest way to build apps with Next.js and Supabase",
};

const geistSans = Geist({
  variable: "--font-geist-sans",
  display: "swap",
  subsets: ["latin"],
});

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${geistSans.className} antialiased`}>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
