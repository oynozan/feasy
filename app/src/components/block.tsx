"use client";

import type { ReactNode } from "react";
import { AnimatePresence, motion } from "motion/react";
import { Card } from "@/components/ui/card";
import { pop, rise, springy } from "@/lib/motion";
import { cn } from "@/lib/utils";

/*
 * Every block shares one row grid so its parts line up across the two columns.
 * Header 36px, then 32px down a 24px eyebrow, a 48px figure and a 32px chip,
 * and the primary action pinned to the bottom edge.
 */

export function Block({ className, children }: { className?: string; children: ReactNode }) {
    return <Card className={cn("h-full gap-0 rounded-block p-6 shadow-none ring-0", className)}>{children}</Card>;
}

export function BlockHeader({ children }: { children: ReactNode }) {
    return (
        <div data-row="header" className="flex h-9 shrink-0 items-center justify-between gap-3">
            {children}
        </div>
    );
}

export function BlockLabel({ children }: { children: ReactNode }) {
    return <h2 className="text-[15px] leading-6 font-medium text-muted-foreground">{children}</h2>;
}

export function Eyebrow({ children }: { children: ReactNode }) {
    return (
        <div data-row="eyebrow" className="mt-8 flex h-6 items-center gap-2 text-[15px] text-muted-foreground">
            {children}
        </div>
    );
}

export function FigureRow({ children }: { children: ReactNode }) {
    return (
        <div data-row="figure" className="mt-2 flex h-12 items-center">
            {children}
        </div>
    );
}

export function ChipRow({ children }: { children: ReactNode }) {
    return (
        <div data-row="chip" className="mt-3 flex h-8 items-center">
            {children}
        </div>
    );
}

export function Chip({ children, tone = "flat" }: { children: ReactNode; tone?: "gain" | "flat" }) {
    return (
        <motion.span
            className={cn(
                "inline-flex h-8 items-center gap-1.5 rounded-full px-3 text-[15px] font-medium whitespace-nowrap tabular-nums",
                tone === "gain" ? "bg-second text-foreground" : "bg-secondary text-muted-foreground",
            )}
            initial={{ opacity: 0, scale: 0.85 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.9 }}
            transition={pop}
        >
            {children}
        </motion.span>
    );
}

// Springs a control on hover and press, still when it is disabled
export function Press({
    className,
    disabled,
    children,
}: {
    className?: string;
    disabled?: boolean;
    children: ReactNode;
}) {
    return (
        <motion.div
            className={cn("flex *:flex-1", className)}
            whileHover={disabled ? undefined : { scale: 1.03 }}
            whileTap={disabled ? undefined : { scale: 0.95 }}
            transition={springy}
        >
            {children}
        </motion.div>
    );
}

// Swaps a placeholder for its content with a short rise, keeping the same footprint
export function Reveal({
    ready,
    placeholder,
    children,
}: {
    ready: boolean;
    placeholder: ReactNode;
    children: ReactNode;
}) {
    return (
        <AnimatePresence mode="popLayout" initial={false}>
            {ready ? (
                <motion.div
                    key="ready"
                    initial={{ opacity: 0, y: 10, filter: "blur(6px)" }}
                    animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                    transition={rise}
                >
                    {children}
                </motion.div>
            ) : (
                <motion.div key="waiting" exit={{ opacity: 0, transition: { duration: 0.12 } }}>
                    {placeholder}
                </motion.div>
            )}
        </AnimatePresence>
    );
}

// One right-side view, rising in when it is picked and sinking out when it is left
export function View({ children }: { children: ReactNode }) {
    return (
        <motion.div
            className="flex h-full flex-col gap-3 [&>*:last-child]:flex-1"
            initial={{ opacity: 0, y: 28, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -16, scale: 0.97, transition: { duration: 0.16 } }}
            transition={rise}
        >
            {children}
        </motion.div>
    );
}
