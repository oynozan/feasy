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
                    <div className={block}>
                        <div className="flex h-9 items-center">
                            <Wordmark />
                        </div>
                    </div>
                }
                right={
                    pathname === "/deposit" || pathname === "/withdraw" ? (
                        <div className={block} />
                    ) : (
                        <div className="flex h-full flex-col gap-3">
                            <div className="grid shrink-0 gap-3 sm:grid-cols-2 lg:h-[284px] lg:grid-rows-2 [&>*]:min-h-[136px]">
                                <div className={block} />
                                <div className={`${block} sm:row-span-2`} />
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
