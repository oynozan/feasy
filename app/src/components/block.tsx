"use client";

import type { ReactNode } from "react";
import { motion, type Transition } from "motion/react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export const rise: Transition = { type: "spring", visualDuration: 0.45, bounce: 0.25 };

export function Block({ className, children }: { className?: string; children: ReactNode }) {
    return <Card className={cn("gap-0 rounded-block p-6 shadow-none ring-0", className)}>{children}</Card>;
}

export function BlockLabel({ children }: { children: ReactNode }) {
    return <h2 className="text-[15px] font-medium text-muted-foreground">{children}</h2>;
}

// One right-side view, rising in when it is picked and sinking out when it is left
export function View({ children, className }: { children: ReactNode; className?: string }) {
    return (
        <motion.div
            className={cn("flex flex-1 flex-col gap-3 [&>*:last-child]:flex-1", className)}
            initial={{ opacity: 0, y: 24, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -12, scale: 0.98, transition: { duration: 0.15 } }}
            transition={rise}
        >
            {children}
        </motion.div>
    );
}
