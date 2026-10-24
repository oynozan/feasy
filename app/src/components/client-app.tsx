"use client";

import dynamic from "next/dynamic";
import { Frame } from "./frame";

// The Bitcoin wallet SDKs touch window as soon as they load, so the whole app renders in the browser
export const ClientApp = dynamic(() => import("./app").then((m) => m.App), { ssr: false, loading: Shell });

function Shell() {
    return (
        <div aria-busy="true" aria-label="Loading">
            <Frame
                left={<div className="h-[420px] animate-pulse rounded-block bg-card" />}
                right={
                    <div className="grid gap-3 sm:grid-cols-2">
                        <div className="h-[200px] animate-pulse rounded-block bg-card" />
                        <div className="h-[200px] animate-pulse rounded-block bg-card" />
                    </div>
                }
            />
        </div>
    );
}
