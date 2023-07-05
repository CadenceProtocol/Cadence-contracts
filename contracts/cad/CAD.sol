// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract CAD is MintableBaseToken {
    constructor() public MintableBaseToken("CAD", "CAD", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "CAD";
    }
}
