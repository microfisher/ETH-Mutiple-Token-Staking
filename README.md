# ETH-Mutiple-Token-Staking
ETH可乐质押系统，支持ETH及ERC20代币质押并生成锚定币

#### 一、用户质押
1.防止重入漏洞  
2.验证最小质押量、验证代币是否支持质押、验证系统锁定状态、验证是否强制倍数质押  
3.支持ETH、ERC20多币种质押  
4.支持大户、散户质押  
5.每32个ETH生成一笔订单（id唯一）并生成事件，超出或不足32ETH的单独生成订单（mutiple需设置为false）  
6.建立用户-订单的映射关系（为了降低gas采用单向映射）  
7.生成锚定币  
```
用户充值
function deposit(string memory name, uint256 amount) public payable nonReentrant  
  
name 代币名称（ETH、USDT、DAI）  
amount 质押数量 （ETH质押时可设置为0，ERC20质押时需设置具体数值）  
```

#### 二、用户提取
1.防止重入漏洞  
2.验证当前状态是否可提现、验证当前币种是否存在、验证系统锁定状态、验证本人是否有可提数量，分别验证合约ERC20及ETH余额是否足够提现  
3.销毁锚定币  
4.移除订单信息  
5.区分ETH及ERC20转账方式，给用户提现  
```
用户提现
function withdraw(string memory name, uint256[] ids) public nonReentrant
  
name 代币名称（ETH、USDT、DAI）  
ids 存款凭证ID列表 （用户质押时生成的唯一ID，会通过事件保存至后端服务器）  
```

#### 三、转移并创建节点
1.验证资金账户地址不为0、验证是否服务账号在执行操作、验证是否支持转移代币、验证订单id列表是否正确    
2.根据订单id列表计算要转移的代币数量  
3.按币种检查合约余额是否充足  
4.更新订单状态为不可提取（用户无法提现）  
5.转移代币至资金账户  
```
后台转出代币并创建节点
function transfer(string memory name, uint256[] memory ids) public nonReentrant
  
name 代币名称（ETH、USDT、DAI）  
ids 存款凭证ID数组列表 （需要转出并创建节点的id列表，因为要更新每位用户存款的状态，这里支持批量传入id，降低gas消耗）  
```

#### 四、转入并更新状态
1.首先转入需要提现的代币至合约（后端计算好后转入）  
2.更新需要提现的订单的状态为可提取  
3.用户现在可以销毁锚定币提现  
```
后台转入代币并更新状态
function unstake(string memory name, uint256[] memory ids) public nonReentrant 
  
name 代币名称（ETH、USDT、DAI）  
ids 存款凭证ID数组列表 （需要转入并给用户提现的id列表，此方法仅更新存款凭证状态，这里支持批量传入id，降低gas消耗）  
```

#### 五、管理支持质押的代币列表
1.可添加多个币种及兑换汇率  
2.支持多个币种以不同的兑换率生成锚定币  
3.支持倍数质押、非倍数质押  
4.支持最大最小值  
5.支持兑换汇率设置  
```
创建、修改代币信息（存在则更新，不存在则创建）
function setToken(string memory name, bool multiple, uint32 numerator, uint32 denominator, address input, address output, uint256 minimum, uint256 maximum) public
  
name 代币名称（ETH、USDT、DAI）  
multiple 是否质押数量必须是节点最大质押量的倍数(默认为true)  
numerator 兑换比例分子（默认1）  
denominator 兑换比例的分母（默认1）  
input 质押代币合约地址（ETH、USDT、DAI....）  
output 生成锚定币合约地址（KLETH、KLUSDT、KLDAI....） 
minimum 节点最小质押数量(默认32 = 32 * 1e18)  
maximum 节点最大质押数量(默认32 = 32 * 1e18)  

移除代币信息
function removeToken(string memory name) public
name 代币名称（ETH、USDT、DAI） 
```

#### 六、系统设置
1.锁定充值、提现操作  
2.更换资金账户地址  
3.更换服务账户地址  
4.更换管理账户地址  
```
修改系统设置
function changeSetting(bool locked, address server, address manager, address funds) public 
  
locked 是否锁定合约（默认false，锁定后充值、提现均无法操作）   
server 服务端操作地址  
manager 管理员操作地址  
funds 资金管理地址  

锁定、解锁系统
function lock() public

```

#### 七、其他操作
1.支持紧急提现用户资金至系统设置的资金账户  
```
紧急提现操作  
function emergency(string memory name) public  
  
name 代币名称（ETH、USDT、DAI）     

获取系统信息  
function getSettingInfo() public view returns (Setting memory setting)  

获取代币信息  
function getTokenInfo(string memory name) public view returns (Token memory token)  

获取订单信息  
function getOrderInfo(uint256 id) public view returns (Order memory order)  

获取批量订单总金额  
function getOrderAmount(uint256[] memory ids) public view returns (uint256)  

```

