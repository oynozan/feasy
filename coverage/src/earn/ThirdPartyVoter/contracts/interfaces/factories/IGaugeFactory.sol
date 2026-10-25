// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IStakingGaugeFactory} from "./IStakingGaugeFactory.sol";
import {INonStakingGaugeFactory} from "./INonStakingGaugeFactory.sol";

interface IGaugeFactory is IStakingGaugeFactory, INonStakingGaugeFactory {}
