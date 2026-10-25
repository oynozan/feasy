import type { Metadata } from "next";
import { Layout, Navbar } from "nextra-theme-docs";
import { Head } from "nextra/components";
import { getPageMap } from "nextra/page-map";
import { ArrowUpRightIcon } from "@heroicons/react/16/solid";
import { sans } from "./fonts";
import "nextra-theme-docs/style.css";
import "katex/dist/katex.min.css";
import "./globals.css";

const APP = "https://feasy.org";
const DOCS = "https://docs.feasy.org";
const REPO = "https://github.com/oynozan/feasy";

export const metadata: Metadata = {
    metadataBase: new URL(DOCS),
    title: { default: "Feasy Docs", template: "%s – Feasy Docs" },
    description: "How Feasy, the BTC savings vault on Mezo, works: the loan, the savings, the veBTC sleeve and the math behind them.",
};

function Logo() {
    return (
        <span className="logo">
            <svg viewBox="0 0 480 560" fill="currentColor" aria-hidden="true">
                <path d="M0 160 L160 0 L480 0 L360 120 L160 120 L0 280 Z" />
                <path d="M0 360 L160 200 L360 200 L240 320 L160 320 L84.853 395.147 L84.853 475.147 L0 560 Z" />
            </svg>
            <span className="logo-name">Feasy</span>
            <span className="logo-chip">Docs</span>
        </span>
    );
}

const navbar = (
    <Navbar logo={<Logo />} projectLink={REPO}>
        <a className="open-app" href={APP}>
            Open app
            <ArrowUpRightIcon />
        </a>
    </Navbar>
);

const footer = (
    <footer className="site-footer">
        <div className="site-footer-top">
            <div className="site-footer-brand">
                <Logo />
                <p>Deposit BTC, get more BTC.</p>
            </div>
            <nav aria-label="Feasy links">
                <a href={APP}>App</a>
                <a href={DOCS}>Docs</a>
                <a href={REPO}>GitHub</a>
                <a href="https://mezo.org">Mezo</a>
            </nav>
        </div>
        <div className="site-footer-base">
            <span>© {new Date().getFullYear()} Feasy</span>
            <span>Unaudited, live on Mezo testnet</span>
        </div>
    </footer>
);

export default async function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html lang="en" dir="ltr" className={sans.variable} suppressHydrationWarning>
            <Head
                color={{ hue: 44, saturation: 100, lightness: 48 }}
                backgroundColor={{ light: "#ede8ec", dark: "#ede8ec" }}
            />
            <body>
                <Layout
                    navbar={navbar}
                    footer={footer}
                    pageMap={await getPageMap()}
                    docsRepositoryBase={`${REPO}/tree/main/docs-site`}
                    editLink="Edit this page"
                    feedback={{ content: null }}
                    darkMode={false}
                    nextThemes={{ forcedTheme: "light" }}
                    sidebar={{ defaultMenuCollapseLevel: 1 }}
                >
                    {children}
                </Layout>
            </body>
        </html>
    );
}
