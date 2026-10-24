"use client";

import { useState, type ReactNode } from "react";
import { QuestionMarkCircleIcon } from "@heroicons/react/16/solid";
import { AnimatePresence, motion } from "motion/react";
import { Card } from "@/components/ui/card";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { pop, rise, springy } from "@/lib/motion";
import { cn } from "@/lib/utils";

/*
 * Every block shares one row grid so its parts line up across the two columns.
 * Header 36px, then 32px down a 24px eyebrow, a 48px figure and a 32px chip,
 * and the primary action pinned to the bottom edge.
 */

export function Block({ className, children, ...rest }: React.ComponentProps<"div">) {
    return (
        <Card className={cn("h-full gap-0 rounded-block p-6 shadow-none ring-0", className)} {...rest}>
            {children}
        </Card>
    );
}

export function BlockHeader({ children }: { children: ReactNode }) {
    return (
        <div data-row="header" className="flex h-9 shrink-0 items-center justify-between gap-3">
            {children}
        </div>
    );
}

export function BlockLabel({ children, tip }: { children: ReactNode; tip?: ReactNode }) {
    return (
        <div className="flex items-center gap-1.5">
            <h2 className="text-[15px] leading-6 font-medium text-muted-foreground">{children}</h2>
            {tip && <InfoTip>{tip}</InfoTip>}
        </div>
    );
}

// A question mark that explains its block in a plain sentence, opened by hover, focus or tap
function InfoTip({ children }: { children: ReactNode }) {
    const [open, setOpen] = useState(false);
    return (
        <Tooltip open={open} onOpenChange={setOpen}>
            <TooltipTrigger asChild>
                <motion.button
                    type="button"
                    aria-label="What is this?"
                    onClick={() => setOpen((was) => !was)}
                    className="grid size-6 place-items-center rounded-full text-muted-foreground transition-colors outline-none hover:text-foreground focus-visible:text-foreground"
                    whileHover={{ scale: 1.15 }}
                    whileTap={{ scale: 0.9 }}
                    transition={springy}
                >
                    <QuestionMarkCircleIcon className="size-4" />
                </motion.button>
            </TooltipTrigger>
            <TooltipContent
                side="top"
                sideOffset={6}
                className="max-w-64 bg-primary px-3.5 py-2.5 text-[13px] leading-5 text-primary-foreground [&_svg]:bg-primary [&_svg]:fill-primary"
            >
                <motion.span
                    initial={{ opacity: 0, scale: 0.9, y: 4 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    transition={pop}
                >
                    {children}
                </motion.span>
            </TooltipContent>
        </Tooltip>
    );
}

export function Eyebrow({ children, className }: { children: ReactNode; className?: string }) {
    return (
        <div
            data-row="eyebrow"
            className={cn("mt-8 flex h-6 items-center gap-2 text-[15px] text-muted-foreground", className)}
        >
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
                tone === "gain" ? "bg-highlight text-foreground" : "bg-secondary text-muted-foreground",
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
