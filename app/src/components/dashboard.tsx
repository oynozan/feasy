"use client";

import { AnimatePresence, MotionConfig } from "motion/react";
import { usePathname } from "next/navigation";
import { useAccount } from "wagmi";
import { View } from "./block";
import { Activity } from "./blocks/activity";
import { Balance } from "./blocks/balance";
import { Deposit, Withdraw } from "./blocks/amount";
import { Loan } from "./blocks/loan";
import { Yield } from "./blocks/yield";
import { Frame } from "./frame";

// The balance stays put on the left, only the right side changes with the URL
export function Dashboard() {
    const pathname = usePathname();
    const { isConnected } = useAccount();

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
                                <div className="grid gap-3 sm:grid-cols-2">
                                    <Yield />
                                    <Loan />
                                </div>
                                {isConnected && <Activity />}
                            </View>
                        )}
                    </AnimatePresence>
                }
            />
        </MotionConfig>
    );
}
