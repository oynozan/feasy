import type { NextConfig } from "next";

const nextConfig: NextConfig = {
    // A self-contained server.js for the Docker image
    output: "standalone",
    cacheComponents: true,
    partialPrefetching: true,
    reactCompiler: true,
    // Ships only TypeScript source
    transpilePackages: ["@mezo-org/orangekit-contracts"],
    turbopack: {
        rules: {
            "*.css": {
                loaders: ["@tailwindcss/turbopack"],
                as: "*.css",
            },
        },
        resolveAlias: {
            // Passport's orangekit re-exports the chains from a TypeScript source path that ships compiled
            "@mezo-org/orangekit-smart-account/src/lib/utils/chains":
                "@mezo-org/orangekit-smart-account/dist/src/lib/utils/chains.js",
        },
    },
};

export default nextConfig;
