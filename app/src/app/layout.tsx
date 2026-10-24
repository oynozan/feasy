import type { Metadata } from "next";
import { Google_Sans } from "next/font/google";
import { ClientApp } from "@/components/client-app";
import "./globals.css";

const sans = Google_Sans({ subsets: ["latin"], variable: "--font-google-sans" });

export const metadata: Metadata = {
    title: { default: "Feasy", template: "%s – Feasy" },
    description: "Deposit BTC, get more BTC.",
};

// A wallet wagmi will reconnect keeps the white look, everyone else starts on the gold one
const THEME = `try{var s=JSON.parse(localStorage.getItem("wagmi.store")||"{}");if(!(s.state&&s.state.connections&&s.state.connections.value&&s.state.connections.value.length))document.documentElement.dataset.theme="pool"}catch(e){document.documentElement.dataset.theme="pool"}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
    return (
        <html lang="en" className={sans.variable} suppressHydrationWarning>
            <head>
                <script dangerouslySetInnerHTML={{ __html: THEME }} />
            </head>
            <body>
                {children}
                <ClientApp />
            </body>
        </html>
    );
}
