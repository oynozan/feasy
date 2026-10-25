import nextra from "nextra";

const withNextra = nextra({
    latex: true,
    defaultShowCopyCode: true,
});

export default withNextra({
    // A self-contained server.js for the Docker image
    output: "standalone",
    turbopack: {
        resolveAlias: {
            // Draws ```mermaid blocks with pele instead of mermaid.js
            "@theguild/remark-mermaid/mermaid": "./components/mermaid.tsx",
        },
    },
});
