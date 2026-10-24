"use client";

import type { ReactNode } from "react";
import "@rainbow-me/rainbowkit/styles.css";
import { lightTheme, RainbowKitProvider, type AvatarComponent, type Theme } from "@rainbow-me/rainbowkit";
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
import { TooltipProvider } from "@/components/ui/tooltip";
import "@/lib/relayer";

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
});

const queryClient = new QueryClient();

// RainbowKit's light theme redrawn in the app's own tokens: flat like the blocks, no drop shadows
const base = lightTheme({ borderRadius: "large", overlayBlur: "small" });
const theme: Theme = {
    ...base,
    fonts: { body: "var(--font-google-sans), system-ui, sans-serif" },
    radii: { ...base.radii, modal: "34px", modalMobile: "34px" },
    colors: {
        ...base.colors,
        accentColor: "var(--gray)",
        accentColorForeground: "var(--white)",
        actionButtonBorder: "transparent",
        actionButtonBorderMobile: "transparent",
        actionButtonSecondaryBackground: "var(--secondary)",
        closeButton: "var(--muted-foreground)",
        closeButtonBackground: "var(--secondary)",
        connectionIndicator: "var(--gold)",
        error: "var(--danger)",
        generalBorder: "var(--border)",
        generalBorderDim: "var(--secondary)",
        menuItemBackground: "var(--secondary)",
        modalBackdrop: "color-mix(in oklab, var(--black) 32%, transparent)",
        modalBackground: "var(--white)",
        modalText: "var(--black)",
        modalTextDim: "color-mix(in oklab, var(--black) 36%, var(--white))",
        modalTextSecondary: "var(--muted-foreground)",
        profileAction: "var(--secondary)",
        profileActionHover: "color-mix(in oklab, var(--secondary), var(--black) 5%)",
        profileForeground: "var(--white)",
        selectedOptionBorder: "transparent",
        standby: "var(--gold)",
    },
    shadows: {
        connectButton: "none",
        dialog: "none",
        profileDetailsAction: "none",
        selectedOption: "none",
        selectedWallet: "none",
        walletLogo: "none",
    },
};

// The gold of the wallet pill's dot in place of RainbowKit's emoji avatars
const Avatar: AvatarComponent = ({ size }) => (
    <span className="grid place-items-center rounded-full bg-gold" style={{ width: size, height: size }}>
        <svg viewBox="0 0 480 560" fill="currentColor" aria-hidden="true" style={{ height: size * 0.4 }}>
            <path d="M0 160 L160 0 L480 0 L360 120 L160 120 L0 280 Z" />
            <path d="M0 360 L160 200 L360 200 L240 320 L160 320 L84.853 395.147 L84.853 475.147 L0 560 Z" />
        </svg>
    </span>
);

export function Providers({ children }: { children: ReactNode }) {
    return (
        <WagmiProvider config={config}>
            <QueryClientProvider client={queryClient}>
                <RainbowKitProvider theme={theme} avatar={Avatar} initialChain={mezoTestnet} modalSize="compact">
                    <TooltipProvider delayDuration={120}>{children}</TooltipProvider>
                </RainbowKitProvider>
            </QueryClientProvider>
        </WagmiProvider>
    );
}
