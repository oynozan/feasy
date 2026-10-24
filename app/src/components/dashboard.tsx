"use client";

import { useEffect } from "react";
import { AnimatePresence, MotionConfig } from "motion/react";
import { usePathname } from "next/navigation";
import { useAccount } from "wagmi";
import { useVaultTx } from "@/lib/hooks";
import { View } from "./block";
import { Activity, HowItWorks } from "./blocks/activity";
import { Deposit, Withdraw } from "./blocks/amount";
import { Balance } from "./blocks/balance";
import { Loan } from "./blocks/loan";
import { Yield } from "./blocks/yield";
import { Frame } from "./frame";

// The balance stays put on the left, only the right side changes with the URL
export function Dashboard() {
    const pathname = usePathname();
    const { status } = useAccount();
    const tx = useVaultTx();
    const settled = tx.state.status === "done" || tx.state.status === "error";

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
                                <div className="grid shrink-0 gap-3 sm:grid-cols-2 lg:h-[212px] [&>*]:min-h-[212px]">
                                    <Yield />
                                    <Loan />
                                </div>
                                {status === "disconnected" ? <HowItWorks /> : <Activity />}
                            </View>
                        )}
                    </AnimatePresence>
                }
            />
        </MotionConfig>
    );
}
