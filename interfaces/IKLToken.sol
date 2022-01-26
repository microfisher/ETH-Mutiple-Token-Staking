//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IKLToken is IERC20 {

    function mint(address owner,uint256 amount) external;

    function burn(address owner,uint256 amount) external;

}