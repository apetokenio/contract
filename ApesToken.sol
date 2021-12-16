// SPDX-License-Identifier: apestoken.io

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


contract ApesToken is Context, IERC20, Ownable {
    event CommunityRewardSent(address indexed to, uint256 value);    

    using SafeMath for uint256;
    using Address for address;

    address public marketingAddress = 0xFC79F74d7D5385234c45786c50e0bb333F3E10be; // Marketing Address
    address public communityRewardAddress = 0x43d5b70520F4e436203eE104d6c96282443171fa; // communityRewardAddress Address

    address public dexRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E; 

    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isSniper;
    address[] private _confirmedSnipers;


    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
   
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1000000000* 10**9; //1 Billion Token supply
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "ApesToken";
    string private _symbol = "APES";
    uint8 private _decimals = 9;

    uint8 private _taxFee = 4;
    uint8 private _previousTaxFee = _taxFee;
    
    uint8 private _communityRewardFee = 4;
    uint8 private _previousCommunityRewardFee = _communityRewardFee;
    
    uint8 private _marketingFee = 2;
    uint8 private _previousMarketingFee = _marketingFee;

    mapping (address => bool) private liqPairs;
    address public liqPairMain;
   
    bool private _takeFeeOnBuy = true;
    bool private _takeFeeOnSell = true;
    bool private _takeFeeOnTransfer = false;
   

    /*
    * Reflection Contract with:
    * - taxFee token goes to all hodlers (exept liqPools and communityReward address)
    * - communityRewardFees token goes to the contract address and can bee distributed to with z_transferCommunityRewards
    * - marketingFee token goes to the marketingAddress
    *
    *
    *
    * Steps to launch:
    *   0. 
    *   1. deploy contract.
    *   2. call z_initLiqPair(routerAddress), this will open the standrd liqPool
    *   3. add Liq
    *   4. set _takeFeeOnTransfer to true
    *
    *   call z_setLiqPair(addressOfLiqPool, true) for each new liqPool.
    *
    *
    */
    constructor () {
        _rOwned[_msgSender()] = _rTotal; //mint all to deployer
        emit Transfer(address(0), _msgSender(), _tTotal);
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[communityRewardAddress] = true;
        _isExcludedFromFee[marketingAddress] = true;
        _isExcludedFromFee[burnAddress] = true;
        z_excludeFromReward(communityRewardAddress);
    }

    function z_initLiqPair(address _dexRouter) external onlyOwner() {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_dexRouter);
        liqPairMain = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        liqPairs[liqPairMain] = true;
        z_excludeFromReward(liqPairMain);
        dexRouter = _dexRouter;
        _isExcludedFromFee[_dexRouter] = true; //no fees for new liqPools
    }
    


    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }
    
  
    
    function reflect(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }
  

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function z_excludeFromReward(address account) public onlyOwner() {

        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function z_includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!_isSniper[from], "Blocked by anti bot (from)!");
        require(!_isSniper[msg.sender], "Blocked by anti bot (msg.sender)!");
        require(from != burnAddress, "Sorry, your the burnAddress!");
        
        
        bool takeFee = _takeFeeOnTransfer;
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        } else {
            if(liqPairs[from]) {
                takeFee = _takeFeeOnBuy;
            } else if(liqPairs[to] && balanceOf(to)>0) {
                takeFee = _takeFeeOnSell;
            }
        }
        
        _tokenTransfer(from, to, amount, takeFee);
    }

 
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeCommunityReward(tCommunityReward);
        _takeMarketing(tMarketing);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeCommunityReward(tCommunityReward);
        _takeMarketing(tMarketing);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeCommunityReward(tCommunityReward);
        _takeMarketing(tMarketing);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeCommunityReward(tCommunityReward);
        _takeMarketing(tMarketing);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tCommunityReward, tMarketing, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tCommunityReward, tMarketing);
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256) {
        uint256 tFee = _calculateTaxFee(tAmount);
        uint256 tCommunityReward = _calculateCommunityRewardFee(tAmount);
        uint256 tMarketing = _calculateMarketingFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tCommunityReward).sub(tMarketing);
        return (tTransferAmount, tFee, tCommunityReward, tMarketing);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tCommunityReward, uint256 tMarketing, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rCommunityReward = tCommunityReward.mul(currentRate);
        uint256 rMarketing = tMarketing.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rCommunityReward).sub(rMarketing);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeCommunityReward(uint256 tCommunityReward) private {
        uint256 currentRate =  _getRate();
        uint256 rCommunityReward = tCommunityReward.mul(currentRate);
        _rOwned[communityRewardAddress] = _rOwned[communityRewardAddress].add(rCommunityReward);
        if(_isExcluded[communityRewardAddress])
            _tOwned[communityRewardAddress] = _tOwned[communityRewardAddress].add(tCommunityReward);
    }

     function _takeMarketing(uint256 tMarketing) private {
        uint256 currentRate =  _getRate();
        uint256 rMarketing = tMarketing.mul(currentRate);
        _rOwned[marketingAddress] = _rOwned[marketingAddress].add(rMarketing);
        if(_isExcluded[marketingAddress])
            _tOwned[marketingAddress] = _tOwned[marketingAddress].add(tMarketing);
    }



    //this is really a "soft" burn (total supply is not reduced).
    function burn(uint256 amount) external {

        address sender = _msgSender();
        require(sender != address(0), "Token: burn from the zero address");
        require(sender != address(burnAddress), "BaseRfiToken: burn from the burn address");

        uint256 balance = balanceOf(sender);
        require(balance >= amount, "Token: burn amount exceeds balance");
        
        _tokenTransfer(sender, burnAddress, amount, false);  //transfer token to dead address, without taking fees.

    }
    

    function _calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(
            10**2
        );
    }
    
    function _calculateCommunityRewardFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_communityRewardFee).div(
            10**2
        );
    }
    
    function _calculateMarketingFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_marketingFee).div(
            10**2
        );
    }

    function removeAllFee() private {
        if(_taxFee == 0 && _communityRewardFee == 0 && _marketingFee == 0) return;
        
        _previousTaxFee = _taxFee;
        _previousCommunityRewardFee = _communityRewardFee;
        _previousMarketingFee = _marketingFee;

        _taxFee = 0;
        _communityRewardFee = 0;
        _marketingFee = 0;
    }
    
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _communityRewardFee = _previousCommunityRewardFee;
        _marketingFee = _previousMarketingFee;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }
    

    function z_excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function z_includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }
    

    function z_setFees(uint8 taxFee, uint8 communityRewardFee, uint8 marketingFee) external onlyOwner() {
        require((taxFee+communityRewardFee+marketingFee)<=20, "ERROR: max fee is 20%");
        _taxFee = taxFee;
        _communityRewardFee = communityRewardFee;
        _marketingFee = marketingFee;
    }
 
    function z_getFees() public view onlyOwner() returns (uint8[] memory)  {
        uint8[] memory result = new uint8[](3);
        result[0] = _taxFee;
        result[1] = _communityRewardFee;
        result[2] = _marketingFee;
        return result;
    } 


    function z_setMarketingAddress(address _marketingAddress) external onlyOwner() {
        marketingAddress = _marketingAddress;
    }

    function z_changeCommunityRewardAddress(address newCommunityRewardAddress, bool transferCurrentBalance) external onlyOwner() {
        if(transferCurrentBalance == true) {
            _tokenTransfer(communityRewardAddress, newCommunityRewardAddress, balanceOf(communityRewardAddress), false);  //transfer current balance of token to newCommunityRewardAddress address, without taking fees.
        }
        communityRewardAddress = newCommunityRewardAddress;
        z_excludeFromReward(communityRewardAddress);
    }
    

    function z_setTakeFees(bool newTakeFeeOnBuy, bool newTakeFeeOnsell, bool newTakeFeeOnTransfer) external onlyOwner() {
        _takeFeeOnBuy = newTakeFeeOnBuy;
        _takeFeeOnSell = newTakeFeeOnsell;
        _takeFeeOnTransfer = newTakeFeeOnTransfer;
    }   

    function z_getTakeFees() public view onlyOwner() returns (bool[] memory)  {
        bool[] memory result = new bool[](3);
        result[0] = _takeFeeOnBuy;
        result[1] = _takeFeeOnSell;
        result[2] = _takeFeeOnTransfer;
        return result;
    }   
    
    function isRemovedSniper(address account) public view returns (bool) {
        return _isSniper[account];
    }
    
    function z_getConfirmedSniper() public view onlyOwner() returns (address[] memory) {
        return _confirmedSnipers;
    }

    function z_removeSniper(address account) external onlyOwner() {
        require(account != 0x10ED43C718714eb63d5aA57B78B54704E256024E, 'We can not blacklist Uniswap');
        require(!_isSniper[account], "Account is already blacklisted");
        _isSniper[account] = true;
        _confirmedSnipers.push(account);
    }

    function z_amnestySniper(address account) external onlyOwner() {
        require(_isSniper[account], "Account is not blacklisted");
        for (uint256 i = 0; i < _confirmedSnipers.length; i++) {
            if (_confirmedSnipers[i] == account) {
                _confirmedSnipers[i] = _confirmedSnipers[_confirmedSnipers.length - 1];
                _isSniper[account] = false;
                _confirmedSnipers.pop();
                break;
            }
        }
    }
 
  
    function z_setRouterAddress(address newRouterAddress) external onlyOwner() {
        _isExcludedFromFee[newRouterAddress] = true; //no fees for new liqPools
        dexRouter = newRouterAddress;
    }
 

    function z_addLiqPair(address pair) external onlyOwner {
        liqPairs[pair] = true;
        z_excludeFromReward(pair);
    }

    function z_removeLiqPair(address pair) external onlyOwner {
        liqPairs[pair] = false;
    }    


    function z_setApprovalForCommunityRewards(address[] memory accounts, uint256[] memory amount) external {
        require(communityRewardAddress==_msgSender() || owner()==_msgSender(), "Ownable: only owner of the contract or communityRewardAddress");
        uint256 length = accounts.length;
        uint256 length2 = amount.length;
        require(length == length2, 'ERROR: Both arrays need to have the the same lenght!');

        for (uint i = 0; i < length; i++) {
            _approve(communityRewardAddress, accounts[i], amount[i]);
        }
    }

    function z_transferCommunityRewards(address[] memory accounts, uint256[] memory amount) external {
        require(communityRewardAddress==_msgSender() || owner()==_msgSender(), "Ownable: only owner of the contract or communityRewardAddress");

        uint256 length = accounts.length;
        uint256 length2 = amount.length;
        require(length == length2, 'ERROR: Both arrays need to have the the same lenght!');

        for (uint i = 0; i < length; i++) {
            //_tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee)
            _tokenTransfer(communityRewardAddress, accounts[i], amount[i], false); //transfer without taking fees
            emit CommunityRewardSent(accounts[i], amount[i]);
        }
    }    
   
    receive() external payable {}

    //emergency withdraw of ETH/BNB unintended send to this contract
    function z_withdraw() public payable onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }    
}
