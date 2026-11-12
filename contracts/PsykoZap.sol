// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.1.0/utils/ReentrancyGuard.sol";

interface IPancakeRouter {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external;
}

interface IPsykoStoreZap {
    struct Coupon {
        uint256 productId;
        address buyer;
        uint16 discountBps;
        uint32 maxUses;
        uint32 maxQuantity;
        uint64 deadline;
        bytes32 salt;
    }
    function buy(uint256 productId, uint256 quantity, address receiver, uint256 maxTotal, bytes32 orderRef, Coupon calldata coupon, bytes calldata signature) external returns (uint256);
}

contract PsykoZap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable psyko;
    IPsykoStoreZap public immutable store;
    IPancakeRouter public immutable router;
    address public immutable wbnb;

    event ZapPurchase(
        address indexed payer,
        address indexed receiver,
        uint256 indexed productId,
        address tokenIn,
        uint256 amountIn,
        uint256 psykoBought,
        uint256 psykoPaid,
        uint256 psykoToBuyer
    );

    error BadPath();
    error NotEnoughPsyko(uint256 bought, uint256 minPsyko);
    error ZeroAddress();
    error NothingToSpend();
    error OnlySelf();

    event BridgeRefund(address indexed bridge, address indexed receiver, address token, uint256 amount);

    constructor(IERC20 psyko_, IPsykoStoreZap store_, IPancakeRouter router_, address wbnb_) {
        if (address(psyko_) == address(0) || address(store_) == address(0) || address(router_) == address(0) || wbnb_ == address(0)) revert ZeroAddress();
        psyko = psyko_;
        store = store_;
        router = router_;
        wbnb = wbnb_;
    }

    struct Order {
        uint256 productId;
        uint256 quantity;
        address receiver;
        uint256 minPsyko;
        bytes32 orderRef;
        uint256 deadline;
    }

    function buyWithBNB(Order calldata o) external payable nonReentrant returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = address(psyko);
        uint256 before = psyko.balanceOf(address(this));
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(0, path, address(this), o.deadline);
        uint256 bought = psyko.balanceOf(address(this)) - before;
        return _settle(o, msg.sender, address(0), msg.value, bought);
    }

    function buyWithToken(uint256 amountIn, address[] calldata path, Order calldata o) external nonReentrant returns (uint256) {
        _checkPath(path);
        uint256 bought = _swapToken(IERC20(path[0]), amountIn, path, o.deadline);
        return _settle(o, msg.sender, path[0], amountIn, bought);
    }

    function buyFromBridge(address[] calldata path, Order calldata o) external nonReentrant returns (bool purchased) {
        _checkPath(path);
        if (o.receiver == address(0)) revert ZeroAddress();
        IERC20 tin = IERC20(path[0]);
        uint256 amount = tin.allowance(msg.sender, address(this));
        uint256 bal = tin.balanceOf(msg.sender);
        if (bal < amount) amount = bal;
        if (amount == 0) revert NothingToSpend();
        uint256 tb = tin.balanceOf(address(this));
        tin.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = tin.balanceOf(address(this)) - tb;
        try this.settleHeld(msg.sender, path, received, o) {
            return true;
        } catch {
            tin.safeTransfer(o.receiver, received);
            emit BridgeRefund(msg.sender, o.receiver, address(tin), received);
            return false;
        }
    }

    function settleHeld(address payer, address[] calldata path, uint256 amountIn, Order calldata o) external returns (uint256) {
        if (msg.sender != address(this)) revert OnlySelf();
        IERC20 tin = IERC20(path[0]);
        tin.forceApprove(address(router), amountIn);
        uint256 before = psyko.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, address(this), o.deadline);
        tin.forceApprove(address(router), 0);
        uint256 bought = psyko.balanceOf(address(this)) - before;
        return _settle(o, payer, path[0], amountIn, bought);
    }

    function _checkPath(address[] calldata path) internal view {
        if (path.length < 2 || path.length > 4 || path[path.length - 1] != address(psyko) || path[0] == address(psyko)) revert BadPath();
    }

    function _swapToken(IERC20 tin, uint256 amountIn, address[] calldata path, uint256 deadline) internal returns (uint256 bought) {
        uint256 tb = tin.balanceOf(address(this));
        tin.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 received = tin.balanceOf(address(this)) - tb;
        tin.forceApprove(address(router), received);
        uint256 before = psyko.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(received, 0, path, address(this), deadline);
        tin.forceApprove(address(router), 0);
        bought = psyko.balanceOf(address(this)) - before;
    }

    function _settle(Order calldata o, address payer, address tokenIn, uint256 amountIn, uint256 bought) internal returns (uint256 toBuyer) {
        if (o.receiver == address(0)) revert ZeroAddress();
        if (bought < o.minPsyko) revert NotEnoughPsyko(bought, o.minPsyko);
        uint256 start = psyko.balanceOf(address(this));
        psyko.forceApprove(address(store), bought);
        IPsykoStoreZap.Coupon memory none;

        store.buy(o.productId, o.quantity, o.receiver, bought, o.orderRef, none, "");
        psyko.forceApprove(address(store), 0);
        uint256 paid = start - psyko.balanceOf(address(this));
        toBuyer = bought - paid;
        if (toBuyer > 0) psyko.safeTransfer(o.receiver, toBuyer);
        emit ZapPurchase(payer, o.receiver, o.productId, tokenIn, amountIn, bought, paid, toBuyer);
    }
}
