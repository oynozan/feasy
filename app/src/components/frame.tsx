import type { ReactNode } from "react";

// The centered two-column stage, shared by the app and its loading shell
export function Frame({ left, right }: { left: ReactNode; right: ReactNode }) {
    return (
        <main className="flex min-h-dvh items-center justify-center px-4 py-10">
            <div className="grid w-full max-w-[400px] gap-3 lg:max-w-[976px] lg:grid-cols-[400px_1fr]">
                {left}
                <div className="relative flex flex-col">{right}</div>
            </div>
        </main>
    );
}
