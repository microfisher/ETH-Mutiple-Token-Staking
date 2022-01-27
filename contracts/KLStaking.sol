//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IKLToken.sol";

contract KLStaking is ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IKLToken;

    // 支持ERC20代币质押
    struct Token {
        bool multiple;      // 是否质押数量必须是节点最大质押量的倍数(默认为true)
        uint32 numerator;   // 兑换比例分子（默认1）
        uint32 denominator; // 兑换比例的分母（默认1）
        IERC20 input;       // 质押代币合约地址（ETH、USDT、DAI....）
        IKLToken output;    // 生成锚定币合约地址（KLETH、KLUSDT、KLDAI....）
        uint256 minimum;    // 节点最小质押数量(默认32 = 32 * 1e18)
        uint256 maximum;    // 节点最大质押数量(默认32 = 32 * 1e18)
    }

    // 质押订单
    struct Order {
        uint8 status;       // 质押状态（ 0: deposit  1: staked  2: unstaked  3: withdrawal  4: staking  5: unstaking ）
        address token;      // 存款合约
        uint256 amount;     // 质押数量
    }

    // 系统设置
    struct Setting {
        bool locked;        // 是否锁定合约（默认false，锁定后充值、提现均无法操作）
        address server;     // 服务端操作地址
        address manager;    // 管理员操作地址
        address funds;      // 资金管理地址
    }

    // 可质押代币合约列表（ETH、USDT、DAI....）
    mapping(string => Token) private _tokens;

    // 质押订单状态
    mapping(uint256 => address) private _stakeUsers;
    mapping(uint256 => Order) private _stakeOrders;

    // 初始化变量
    Setting private _settings;
    uint256 private _identity;

    // 存款事件
    event OnDeposit(address indexed sender, address indexed token, uint256 indexed id, uint256 time, uint256 staked, uint256 issued);

    // 提款事件
    event OnWithdraw(address indexed sender, address indexed token, uint256[] ids, uint256 time, uint256 burned, uint256 returned);

    // 转移事件
    event OnTransfer(address indexed sender, address indexed token, uint256[] ids, uint256 time, uint256 amount);

    // 更新订单事件
    event OnUnstake(address indexed sender, address indexed token, uint256[] ids, uint256 time, uint256 amount);

    // 设置代币事件
    event OnTokenChange(string indexed name, address indexed input, address indexed output, bool multiple, uint32 numerator, uint32 denominator, uint256 minimum, uint256 maximum);

    // 移除代币事件
    event OnTokenRemove(string indexed name);

    // 系统设置事件
    event OnSettingChange(bool locked, address server, address manager, address funds);

    // 锁定事件
    event OnLockChange(bool locked);


    constructor(address funds, address server, address manager){
        _settings.locked = false;
        _settings.funds = funds;
        _settings.server = server;
        _settings.manager = manager;
    }

    receive() external payable {}

    // 质押代币获得锚定币（用户操作）
    function deposit(string memory name, uint256 amount) public payable nonReentrant {

        require(_settings.locked==false, "The system is currently under maintenance");

        // 判断代币存在
        Token memory token = _tokens[name];
        require(token.numerator>=1, "The token does not exists");

        // 验证质押数量（地址为0则认为ETH质押，反之则认为ERC20代币质押）
        if(address(token.input) == address(0)){
            amount = msg.value;
        }else{
            token.input.safeTransferFrom(msg.sender, address(this), amount); 
        }
        require(amount >= token.minimum, "The amount cannot be less than minimum");

        // 验证质押倍数
        uint256 remain = amount % token.maximum;
        if(token.multiple==true){
            require(remain == 0, "Invalid multiple amount");
        }

        // 创建倍数订单
         uint256 count = amount.div(token.maximum);
        for(uint i=0;i<count;i++){
            _identity = _identity.add(1);
            _stakeUsers[_identity] = msg.sender;
            _stakeOrders[_identity] = Order(0,address(token.input),token.maximum);
            emit OnDeposit(msg.sender, address(token.input), _identity, block.timestamp, token.maximum, token.maximum.div(token.denominator).mul(token.numerator));
        }

        // 创建余数订单
        if(remain>0){
            _identity = _identity.add(1);
            _stakeUsers[_identity] = msg.sender;
            _stakeOrders[_identity] = Order(0,address(token.input),remain);
            emit OnDeposit(msg.sender, address(token.input), _identity, block.timestamp, remain, remain.div(token.denominator).mul(token.numerator));
        }
        
        // 发行锚定币
        uint256 issued = amount.div(token.denominator).mul(token.numerator);
        token.output.mint(msg.sender, issued);
    }

    // 提取代币并销毁锚定币（用户操作）
    function withdraw(string memory name, uint256[] memory ids) public nonReentrant {

        require(_settings.locked==false, "The system is currently under maintenance");

        // 判断代币存在
        Token memory token = _tokens[name];
        require(token.numerator>=1, "The token does not exists");

        // 批量验证提现
        uint256 amount = 0;
        for(uint i=0;i<ids.length;i++){
            uint id = ids[i];
            require(_stakeUsers[id] == msg.sender, "Invalid owner");
            require(_stakeOrders[id].token == address(token.input), "Invalid token");
            require(_stakeOrders[id].amount > 0, "Invalid amount");
            require(_stakeOrders[id].status == 0 || _stakeOrders[id].status == 2, "You cannot withdraw tokens right now");// 0:deposit 2:unstaked 状态才能提现
            amount = amount.add(_stakeOrders[id].amount);
            delete _stakeOrders[id];
            delete _stakeUsers[id];
        }

        // 验证质押数量（地址为0则认为退还ETH代币，反之则认为退还ERC20代币）
        bool isEthToken = address(token.input) == address(0);
        if(isEthToken){
            uint balance = address(this).balance;
            require(balance>=amount,"Insufficient balance");
        }else{
            uint balance = token.input.balanceOf(address(this));
            require(balance>=amount,"Insufficient balance");
        }

        // 转移锚定币
        uint256 burned = amount.div(token.denominator).mul(token.numerator);
        token.output.safeTransferFrom(msg.sender, address(this), burned); 

        // 销毁锚定币
        token.output.burn(address(this), amount);

        // 发送质押币
        if(isEthToken){
            (bool success,) = msg.sender.call{value: amount}("");
            require(success);
        }else{
            token.input.safeTransfer(msg.sender,amount);
        }

        emit OnWithdraw(msg.sender, address(token.input), ids, block.timestamp, burned, amount);
    }

    // 系统转移质押代币并创建节点（系统服务操作）
    function transfer(string memory name, uint256[] memory ids) public nonReentrant {
        
        Token memory token = _tokens[name];
        require(token.numerator>=1, "The token does not exists");
        require(ids.length>0,"Invalid id");
        require(_settings.funds!=address(0),"Invalid funds address");
        require(_settings.server==msg.sender,"Invalid server address");

        // 计算总转移数量，修改用户质押状态（0: deposit  1: staked  2: unstaked  3: withdrawal  4: staking  5: unstaking ）
        uint256 amount = 0;
        for(uint i=0;i<ids.length;i++){
            amount = amount.add(_stakeOrders[ids[i]].amount);
            _stakeOrders[ids[i]].status = 4;// 4:staking
        }

        // 转移代币至资金地址（地址为0则认为转移ETH代币，反之则认为转移ERC20代币）
        bool isEthToken = address(token.input) == address(0);
        if(isEthToken){
            uint balance = address(this).balance;
            require(balance>=amount,"Insufficient balance");
            (bool success,) = _settings.funds.call{value: amount}("");
            require(success);
        }else{
            uint balance = token.input.balanceOf(address(this));
            require(balance>=amount,"Insufficient balance");
            token.input.safeTransfer(_settings.funds,amount);
        }

        emit OnTransfer(msg.sender, address(token.input), ids, block.timestamp, amount);
    }

    // 更新订单状态为取消质押（系统服务操作）
    function unstake(string memory name, uint256[] memory ids) public nonReentrant {
        
        Token memory token = _tokens[name];
        require(token.numerator>=1, "The token does not exists");
        require(ids.length>0,"Invalid id");
        require(_settings.server==msg.sender,"Invalid server address");

        // 修改用户质押状态（0: deposit  1: staked  2: unstaked  3: withdrawal  4: staking  5: unstaking ）
        uint256 amount = 0;
        for(uint i=0;i<ids.length;i++){
            amount = amount.add(_stakeOrders[ids[i]].amount);
            _stakeOrders[ids[i]].status = 2;// 2:unstaked
        }

        emit OnUnstake(msg.sender, address(token.input), ids, block.timestamp, amount);
    }

    // 创建质押代币（管理员操作）
    function setToken(string memory name, bool multiple, uint32 numerator, uint32 denominator, address input, address output, uint256 minimum, uint256 maximum) public {

        Token storage token = _tokens[name];
        require(bytes(name).length>0,"Invalid name");
        require(numerator >= 1,"Invalid numerator");
        require(denominator >= 1,"Invalid denominator");
        require(output != address(0),"Invalid output address");
        require(minimum >0,"Invalid minimum");
        require(maximum >0,"Invalid maximum");
        require(_settings.manager == msg.sender,"Error manager");

        token.multiple = multiple;
        token.numerator = numerator;
        token.denominator = denominator;
        token.input = IERC20(input);
        token.output = IKLToken(output);
        token.minimum = minimum;
        token.maximum = maximum;
        
        emit OnTokenChange(name,address(input),address(output),multiple,numerator,denominator,minimum,maximum);
    }

    // 移除质押代币（管理员操作）
    function removeToken(string memory name) public {
        Token storage token = _tokens[name];
        require(token.numerator>=1,"Token does not exists");
        require(_settings.manager == msg.sender,"Error manager");
        delete _tokens[name];
        emit OnTokenRemove(name);
    }

    // 修改系统设置（管理员操作）
    function changeSetting(bool locked, address server, address manager, address funds) public {
        require(_settings.manager == msg.sender,"Error manager");
        _settings = Setting(locked, server, manager, funds);
        emit OnSettingChange(locked, server, manager, funds);
    }

    // 锁定系统状态（管理员操作）
    function lock() public {
        require(_settings.manager == msg.sender,"Error manager");
        _settings.locked = !_settings.locked;
        emit OnLockChange(_settings.locked);
    }

    // 一键紧急提现（管理员操作）
    function emergency(string memory name) public {
        Token memory token = _tokens[name];
        require(token.numerator>=1, "The token does not exists");
        require(_settings.manager == msg.sender || _settings.server==msg.sender,"Error manager");

        bool isEthToken = address(token.input) == address(0);
        if(isEthToken){
            uint balance = address(this).balance;
            (bool success,) = _settings.funds.call{value: balance}("");
            require(success);
        }else{
            uint balance = token.input.balanceOf(address(this));
            token.input.safeTransfer(_settings.funds,balance);
        }
    }
    
    // 获取系统信息
    function getSettingInfo() public view returns (Setting memory setting) {
        setting = _settings;
    }

    // 获取代币信息
    function getTokenInfo(string memory name) public view returns (Token memory token) {
        token = _tokens[name];
    }
    
    // 获取订单信息
    function getOrderInfo(uint256 id) public view returns (Order memory order) {
        order = _stakeOrders[id];
    }

    // 获取一批订单的总金额
    function getOrderAmount(uint256[] memory ids) public view returns (uint256) {
        uint256 amount = 0;
        for(uint i=0;i<ids.length;i++){
            amount = amount.add(_stakeOrders[ids[i]].amount);
        }
        return amount;
    }
}