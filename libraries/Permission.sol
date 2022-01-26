//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract Permission is Ownable {

    // 操作员列表
    mapping(address => bool) public operators;

    // 合约部署账号及操作员才可以操作
    modifier onlyOperator() {
        require(operators[msg.sender], "Error operator");
        _;
    }

    // 初始化账号
    constructor(address operator){
        createOperator(operator);
    }

    // 创建操作员
    function createOperator(address operator) public onlyOwner {
        operators[operator] = true;
    }

    // 移除操作员
    function removeOperator(address operator) public onlyOwner {
        operators[operator] = false;
    }
}