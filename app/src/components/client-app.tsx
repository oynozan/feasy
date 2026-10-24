"use client";

import dynamic from "next/dynamic";
import { usePathname } from "next/navigation";
import { Frame, Wordmark } from "./frame";

// The Bitcoin wallet SDKs touch window as soon as they load, so the whole app renders in the browser
export const ClientApp = dynamic(() => import("./app").then((m) => m.App), { ssr: false, loading: Shell });

// The same blocks the app opens with, empty, so the first paint already has the final geometry
function Shell() {
    const pathname = usePathname();
    const block = "h-full rounded-block bg-card p-6";
    return (
        <div aria-busy="true" aria-label="Loading">
            <Frame
                left={
                    pathname === "/pool" ? undefined : (
                        <div data-balance="" className={block}>
                            <div className="flex h-9 items-center">
                                <Wordmark />
                            </div>
                        </div>
                    )
                }
                right={
                    pathname === "/pool" ? (
                        <div className="grid h-full gap-3 lg:grid-cols-[400px_1fr]">
                            <div className={`${block} min-h-[480px] lg:min-h-0`}>
                                <div className="flex h-9 items-center">
                                    <Wordmark />
                                </div>
                            </div>
                            <div data-family="" className="grid gap-1.5 sm:grid-cols-2 lg:grid-rows-[136px_136px_1fr]">
                                <div className={`${block} min-h-[136px]`} />
                                <div className={`${block} min-h-[136px]`} />
                                <div className={`${block} min-h-[136px]`} />
                                <div className={`${block} min-h-[136px]`} />
                                <div className={`${block} min-h-[240px] sm:col-span-2`} />
                            </div>
                        </div>
                    ) : pathname === "/deposit" || pathname === "/withdraw" ? (
                        <div data-family="" className="flex h-full flex-col gap-1.5">
                            <div className={`${block} min-h-[136px] shrink-0 lg:h-[136px]`} />
                            <div className={`${block} min-h-[400px] flex-1 lg:min-h-0`} />
                        </div>
                    ) : (
                        <div data-family="" className="flex h-full flex-col gap-1.5">
                            <div className="grid shrink-0 gap-1.5 sm:grid-cols-2 lg:h-[278px] lg:grid-rows-2 [&>*]:min-h-[136px]">
                                <div className={block} />
                                <div className="flex flex-col gap-1.5 sm:row-span-2">
                                    <div className={`${block} flex-1`} />
                                    <div className="min-h-[68px] shrink-0 rounded-block bg-gold lg:h-[68px]" />
                                </div>
                                <div className={block} />
                            </div>
                            <div className={`${block} min-h-[240px] flex-1`} />
                        </div>
                    )
                }
            />
        </div>
    );
}
