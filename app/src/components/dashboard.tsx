"use client";

import { useEffect } from "react";
import { AnimatePresence, MotionConfig } from "motion/react";
import { usePathname } from "next/navigation";
import { useSignedOut, useVaultTx } from "@/lib/hooks";
import { View } from "./block";
import { Activity, HowItWorks } from "./blocks/activity";
import { Deposit, Withdraw } from "./blocks/amount";
import { Balance } from "./blocks/balance";
import { Loan } from "./blocks/loan";
import { PoolSize, Yield } from "./blocks/yield";
import { Frame } from "./frame";

// The balance stays put on the left, only the right side changes with the URL
export function Dashboard() {
    const pathname = usePathname();
    const signedOut = useSignedOut();
    const tx = useVaultTx();
    const settled = tx.state.status === "done" || tx.state.status === "error";

    useEffect(() => {
        if (signedOut) document.documentElement.dataset.theme = "pool";
        else delete document.documentElement.dataset.theme;
    }, [signedOut]);

    // A finished transaction's note belongs to the form it came from, a sent one keeps showing everywhere
    useEffect(() => {
        if (settled) tx.reset();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [pathname]);

    return (
        <MotionConfig reducedMotion="user">
            <Frame
                left={<Balance />}
                right={
                    <AnimatePresence mode="popLayout" initial={false}>
                        {pathname === "/deposit" ? (
                            <View key="deposit">
                                <Deposit />
                            </View>
                        ) : pathname === "/withdraw" ? (
                            <View key="withdraw">
                                <Withdraw />
                            </View>
                        ) : (
                            <View key="home">
                                <div className="grid shrink-0 gap-3 sm:grid-cols-2 lg:h-[284px] lg:grid-rows-2 [&>*]:min-h-[136px]">
                                    <Yield />
                                    <div className="sm:row-span-2">
                                        <Loan />
                                    </div>
                                    <PoolSize />
                                </div>
                                {signedOut ? <HowItWorks /> : <Activity />}
                            </View>
                        )}
                    </AnimatePresence>
                }
            />
        </MotionConfig>
    );
}
