"use client";

import { TxProvider } from "@/lib/hooks";
import { Dashboard } from "./dashboard";
import { Providers } from "./providers";

export function App() {
    return (
        <Providers>
            <TxProvider>
                <Dashboard />
            </TxProvider>
        </Providers>
    );
}
