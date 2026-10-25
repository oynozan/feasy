import { render } from "pele";
import { sans } from "../app/fonts";
import { Diagram } from "./diagram";

// Drawn on the server so the page loads at its final size, the client then adapts it to the width
export function Mermaid({ chart }: { chart: string }) {
    const source = chart.replaceAll("\\n", "\n");
    const { svg } = render(source, { fontFamily: sans.style.fontFamily });
    return <Diagram source={source} svg={svg} />;
}
