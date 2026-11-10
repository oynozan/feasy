"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowDownTrayIcon, ChevronLeftIcon, ChevronRightIcon } from "@heroicons/react/16/solid";
import { Button } from "@/components/ui/button";
import { Wordmark } from "@/components/frame";

// Slides keep 16:9 and never grow taller than the screen leaves room for under the controls
const WIDTH = "w-full max-w-[min(1600px,calc((100dvh-7rem)*16/9))]";

export function Deck({ slides, pdf }: { slides: string[]; pdf: string }) {
    const [index, setIndex] = useState(0);
    const downAt = useRef<number | null>(null);
    const go = useCallback((to: number) => setIndex(Math.max(0, Math.min(slides.length - 1, to))), [slides.length]);

    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") go(index + 1);
            else if (e.key === "ArrowLeft" || e.key === "PageUp") go(index - 1);
            else if (e.key === "Home") go(0);
            else if (e.key === "End") go(slides.length - 1);
        };
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, [go, index, slides.length]);

    return (
        <main className="flex min-h-dvh flex-col items-center justify-center gap-4 bg-background p-4 sm:p-6">
            <div
                className={`${WIDTH} relative aspect-video touch-pan-y overflow-hidden rounded-block bg-card select-none`}
                onPointerDown={(e) => (downAt.current = e.clientX)}
                onPointerUp={(e) => {
                    if (downAt.current === null) return;
                    const dx = e.clientX - downAt.current;
                    downAt.current = null;
                    const box = e.currentTarget.getBoundingClientRect();
                    // A swipe moves one slide, a tap on the right or left half does the same
                    if (Math.abs(dx) > 40) go(index + (dx < 0 ? 1 : -1));
                    else go(index + (e.clientX > box.left + box.width / 2 ? 1 : -1));
                }}
            >
                {slides.map((src, i) => (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                        key={src}
                        src={src}
                        alt={`Slide ${i + 1} of ${slides.length}`}
                        draggable={false}
                        aria-hidden={i !== index}
                        className={`absolute inset-0 size-full object-contain transition-opacity duration-300 ${i === index ? "opacity-100" : "opacity-0"}`}
                    />
                ))}
            </div>
            <nav className={`${WIDTH} flex items-center justify-between gap-3`}>
                <Link href="/" aria-label="Open the Feasy app">
                    <Wordmark />
                </Link>
                <div className="flex items-center gap-2">
                    <Button
                        variant="secondary"
                        size="icon"
                        onClick={() => go(index - 1)}
                        disabled={index === 0}
                        aria-label="Previous slide"
                    >
                        <ChevronLeftIcon />
                    </Button>
                    <span
                        className="min-w-14 text-center text-sm text-muted-foreground tabular-nums"
                        aria-live="polite"
                    >
                        {index + 1} / {slides.length}
                    </span>
                    <Button
                        variant="secondary"
                        size="icon"
                        onClick={() => go(index + 1)}
                        disabled={index === slides.length - 1}
                        aria-label="Next slide"
                    >
                        <ChevronRightIcon />
                    </Button>
                </div>
                <Button asChild variant="secondary">
                    <a href={pdf} download>
                        <ArrowDownTrayIcon />
                        <span className="hidden sm:inline">Download PDF</span>
                        <span className="sm:hidden">PDF</span>
                    </a>
                </Button>
            </nav>
        </main>
    );
}
