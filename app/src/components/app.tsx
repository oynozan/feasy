"use client";

import { Dashboard } from "./dashboard";
import { Providers } from "./providers";

export function App() {
    return (
        <Providers>
            <Dashboard />
        </Providers>
    );
}
