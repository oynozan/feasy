import type { Metadata } from "next";
import { Google_Sans } from "next/font/google";
import { ClientApp } from "@/components/client-app";
import "./globals.css";

const sans = Google_Sans({ subsets: ["latin"], variable: "--font-google-sans" });

export const metadata: Metadata = {
    title: { default: "Feasy", template: "%s – Feasy" },
    description: "Deposit BTC, get more BTC.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
    return (
        <html lang="en" className={sans.variable}>
            <body>
                {children}
                <ClientApp />
            </body>
        </html>
    );
}
