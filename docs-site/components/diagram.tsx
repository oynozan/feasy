"use client";

import { useEffect, useRef } from "react";
import { mount } from "pele";

export function Diagram({ source, svg }: { source: string; svg: string }) {
    const ref = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const diagram = mount(ref.current!, source);
        return () => diagram.destroy();
    }, [source]);

    return <div ref={ref} className="diagram" dangerouslySetInnerHTML={{ __html: svg }} />;
}
