import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

// One fixed stage on wide screens, the balance on the left unless a view takes the whole stage
export function Frame({ left, right }: { left?: ReactNode; right: ReactNode }) {
    return (
        <main className="flex min-h-dvh items-center justify-center px-4 py-10">
            <div
                className={cn(
                    "grid w-full max-w-[400px] gap-3 lg:h-[560px] lg:max-w-[976px]",
                    left && "lg:grid-cols-[400px_1fr]",
                )}
            >
                {left && <div className="flex min-h-[480px] flex-col *:flex-1 lg:min-h-0">{left}</div>}
                <div className="relative flex min-h-0 flex-col *:flex-1">{right}</div>
            </div>
        </main>
    );
}

export function Wordmark() {
    return (
        <div className="flex items-center gap-2">
            <svg viewBox="0 0 480 560" fill="currentColor" aria-hidden="true" className="h-5 w-auto">
                <path d="M0 160 L160 0 L480 0 L360 120 L160 120 L0 280 Z" />
                <path d="M0 360 L160 200 L360 200 L240 320 L160 320 L84.853 395.147 L84.853 475.147 L0 560 Z" />
            </svg>
            <span className="font-heading text-[20px] leading-none font-bold tracking-[-0.02em]">Feasy</span>
            <span className="rounded-full bg-secondary px-2 py-0.5 text-[12px] leading-5 font-medium text-muted-foreground">
                Testnet
            </span>
        </div>
    );
}
