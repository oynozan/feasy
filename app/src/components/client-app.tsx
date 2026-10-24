"use client";

import dynamic from "next/dynamic";

// The Bitcoin wallet SDKs touch window as soon as they load, so the whole app renders in the browser
export const ClientApp = dynamic(() => import("./app").then((m) => m.App), { ssr: false });
