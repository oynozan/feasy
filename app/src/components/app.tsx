"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Providers } from "./providers";

export function App() {
    return (
        <Providers>
            <main className="grid min-h-dvh place-items-center">
                <ConnectButton />
            </main>
        </Providers>
    );
}
