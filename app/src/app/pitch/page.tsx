import { readdirSync } from "node:fs";
import { join } from "node:path";
import type { Metadata } from "next";
import { Deck } from "@/components/deck";

export const metadata: Metadata = {
    title: "Pitch",
    description: "Feasy's pitch deck: a BTC savings vault on Mezo.",
};

// Every slide image in public/pitch shows in name order, so a new slide is just a new file
export default function PitchPage() {
    const slides = readdirSync(join(process.cwd(), "public", "pitch"))
        .filter((name) => name.endsWith(".png"))
        .sort()
        .map((name) => `/pitch/${name}`);
    return <Deck slides={slides} pdf="/pitch/feasy-deck.pdf" />;
}
