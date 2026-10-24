import type { Transition } from "motion/react";

// A bouncy spring (bounce ~0.3) sampled from Motion's physics, for timings that only take CSS easings
const SPRING_EASING =
    "linear(0, 0.0235, 0.0841, 0.169, 0.2677, 0.372, 0.4757, 0.5744, 0.6651, 0.7458, 0.8157, 0.8747, 0.9231, 0.9617, 0.9914, 1.0133, 1.0287, 1.0385, 1.0439, 1.0459, 1.0453, 1.0429, 1.0391, 1.0347, 1.0299, 1.0252, 1.0205, 1.0163, 1.0125, 1.0091, 1.0063, 1.004, 1.0021, 1.0007, 1)";

export const flow = {
    transformTiming: { duration: 700, easing: SPRING_EASING },
    spinTiming: { duration: 700, easing: SPRING_EASING },
};

export const rise: Transition = { type: "spring", visualDuration: 0.45, bounce: 0.25 };
export const pop: Transition = { type: "spring", visualDuration: 0.3, bounce: 0.35 };
export const springy: Transition = { type: "spring", visualDuration: 0.35, bounce: 0.45 };
export const grow: Transition = { type: "spring", visualDuration: 0.6, bounce: 0.25 };
