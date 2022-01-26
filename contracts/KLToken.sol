//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../libraries/Permission.sol";
import "../interfaces/IKLToken.sol";

contract KLToken is ERC20, Permission, IKLToken {

    // 初始化代币，operator是操作员合约地址，需要将主控制合约添加为操作员
    constructor(string memory name,string memory symbol) ERC20(name, symbol) Permission(msg.sender)  {}

    // 发行代币
    function mint(address owner,uint256 amount) public override onlyOperator {
        _mint(owner, amount);
    }

    // 销毁代币
    function burn(address owner,uint256 amount) public override onlyOperator {
        _burn(owner, amount);
    }

}