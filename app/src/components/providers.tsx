"use client";

import type { ReactNode } from "react";
import "@rainbow-me/rainbowkit/styles.css";
import { lightTheme, RainbowKitProvider } from "@rainbow-me/rainbowkit";
import { injectedWallet } from "@rainbow-me/rainbowkit/wallets";
import {
    getConfig,
    okxWalletMezoTestnet,
    unisatWalletMezoTestnet,
    xverseWalletMezoTestnet,
} from "@mezo-org/passport/dist/src/config";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { mezoTestnet } from "viem/chains";
import { http, WagmiProvider } from "wagmi";

const config = getConfig({
    appName: "Feasy",
    mezoNetwork: "testnet",
    // viem's definition carries Multicall3, Passport's does not
    chains: [mezoTestnet],
    walletConnectProjectId: "",
    wallets: [
        { groupName: "Bitcoin", wallets: [unisatWalletMezoTestnet, okxWalletMezoTestnet, xverseWalletMezoTestnet] },
        { groupName: "Ethereum", wallets: [injectedWallet] },
    ],
    // Batched so the balance chart's historical reads share one request, Passport types this key wrong
    transports: { [mezoTestnet.id]: http(mezoTestnet.rpcUrls.default.http[0], { batch: true }) } as never,
    ssr: true,
});

const queryClient = new QueryClient();

const theme = lightTheme({
    accentColor: "#282926",
    accentColorForeground: "#f8f3f8",
    borderRadius: "large",
    fontStack: "system",
});

export function Providers({ children }: { children: ReactNode }) {
    return (
        <WagmiProvider config={config}>
            <QueryClientProvider client={queryClient}>
                <RainbowKitProvider theme={theme} initialChain={mezoTestnet} modalSize="compact">
                    {children}
                </RainbowKitProvider>
            </QueryClientProvider>
        </WagmiProvider>
    );
}
