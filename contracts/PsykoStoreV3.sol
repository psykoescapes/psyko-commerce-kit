// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts@5.1.0/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts@5.1.0/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.1.0/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts@5.1.0/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts@5.1.0/utils/cryptography/SignatureChecker.sol";
import {Math} from "@openzeppelin/contracts@5.1.0/utils/math/Math.sol";
import {PsykoCatalogue} from "./PsykoCatalogue.sol";

interface IPsykoLicense {
    function mint(address to, uint256 id, uint256 amount) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IPancakePair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}

/// @title PSYKO Store v3
/// @notice One checkout for every Psykovsky & Friends album, song and compilation.
///         Every product's collaborators and their shares are written into this contract
///         (see PsykoCatalogue.sol) and can never be changed. Only a payee's wallet address
///         can be moved, by the owner or by the payee, when an artist changes wallets.
///         Part of each price returns to the buyer as cashback, set aside here at the moment
///         of sale and released to the buyer linearly over the cashback period. The owner
///         cannot withdraw set-aside cashback, and pausing sales never blocks claims.
contract PsykoStoreV3 is PsykoCatalogue, Ownable2Step, Pausable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_PAYEES = 32;
    uint16 public constant MAX_CASHBACK_BPS = 5_000;
    uint32 public constant MIN_CASHBACK_DURATION = 1 days;
    uint32 public constant MAX_CASHBACK_DURATION = 365 days;
    uint256 public constant MAX_CLAIM_BATCH = 100;
    uint256 public constant LICENCE_OFFSET = 1000;

    struct Split {
        address payee;
        uint32 share;
    }

    struct Product {
        uint256 price;
        uint256 usdCents;
        uint256 licenceId;
        bool active;
        bool oneLicencePerWallet;
        uint16 cashbackBps;
        Split[] splits;
    }

    struct Coupon {
        uint256 productId;
        address buyer;
        uint16 discountBps;
        uint32 maxUses;
        uint32 maxQuantity;
        uint64 deadline;
        bytes32 salt;
    }

    struct Grant {
        uint128 amount;
        uint128 claimed;
        uint64 start;
        uint64 end;
    }

    bytes32 public constant COUPON_TYPEHASH = keccak256(
        "Coupon(uint256 productId,address buyer,uint16 discountBps,uint32 maxUses,uint32 maxQuantity,uint64 deadline,bytes32 salt)"
    );

    IERC20 public immutable psyko;
    IPsykoLicense public immutable licence;

    uint32 public constant TWAP_PERIOD = 15 minutes;
    uint256 private constant Q112 = 2 ** 112;
    IPancakePair public immutable psykoPair;
    IPancakePair public immutable usdtPair;
    bool private immutable psykoIsToken0;
    bool private immutable wbnbIsToken0;
    struct Twap {
        uint256 cumPsyko;
        uint256 cumUsdt;
        uint32 ts;
        uint224 avgPsyko;
        uint224 avgUsdt;
    }
    Twap public twap;

    address public couponSigner;
    uint32 public cashbackDuration = 90 days;
    uint256 public totalCashbackOwed;
    uint256 public lastProductId;
    mapping(uint256 => Product) private _products;
    mapping(bytes32 => uint32) public couponUses;
    mapping(address => Grant[]) private _grants;
    mapping(address => uint256) public firstOpenGrant;

    event ProductAdded(uint256 indexed productId, uint256 usdCents, uint256 licenceId, uint256 payees);
    event PriceSet(uint256 indexed productId, uint256 price, uint256 usdCents);
    event ActiveSet(uint256 indexed productId, bool active);
    event CashbackSet(uint256 indexed productId, uint16 cashbackBps);
    event CashbackDurationSet(uint32 duration);
    event CouponSignerSet(address signer);
    event PayeeChanged(uint256 indexed productId, address indexed oldPayee, address indexed newPayee);
    event Purchase(
        address indexed payer,
        address indexed receiver,
        uint256 indexed productId,
        uint256 quantity,
        uint256 paid,
        bytes32 couponHash,
        bytes32 orderRef
    );
    event CashbackGranted(address indexed beneficiary, uint256 indexed productId, uint256 amount, uint64 start, uint64 end);
    event CashbackClaimed(address indexed beneficiary, uint256 amount);

    error ProductInactive(uint256 productId);
    error ProductExists(uint256 productId);
    error UnknownProduct(uint256 productId);
    error AlreadyOwned(uint256 productId);
    error PriceAboveMax(uint256 total, uint256 maxTotal);
    error BadSplit();
    error BadQuantity();
    error BadCashback();
    error CouponInvalid();
    error CouponExpired();
    error CouponUsedUp();
    error CouponQuantity();
    error ZeroAddress();
    error NoPool();
    error PriceNotReady();
    error NothingToClaim();
    error EscrowProtected();
    error PayeeNotFound();

    constructor(
        IERC20 psyko_,
        IPsykoLicense licence_,
        address couponSigner_,
        address initialOwner,
        IPancakeFactory factory,
        address wbnb,
        address usdt
    ) Ownable(initialOwner) EIP712("PsykoStore", "3") {
        if (address(psyko_) == address(0) || address(licence_) == address(0)) revert ZeroAddress();
        psyko = psyko_;
        licence = licence_;
        couponSigner = couponSigner_;
        emit CouponSignerSet(couponSigner_);

        require(IERC20Metadata(address(psyko_)).decimals() == 18 && IERC20Metadata(usdt).decimals() == 18, "decimals");
        address pp = factory.getPair(address(psyko_), wbnb);
        address up = factory.getPair(wbnb, usdt);
        if (pp == address(0) || up == address(0)) revert NoPool();
        psykoPair = IPancakePair(pp);
        usdtPair = IPancakePair(up);
        psykoIsToken0 = IPancakePair(pp).token0() == address(psyko_);
        wbnbIsToken0 = IPancakePair(up).token0() == wbnb;
        twap.cumPsyko = _cumNow(IPancakePair(pp), psykoIsToken0);
        twap.cumUsdt = _cumNow(IPancakePair(up), wbnbIsToken0);
        twap.ts = uint32(block.timestamp);

        _seedCatalogue();
    }

    // ------------------------------------------------------------- catalogue

    uint256 private _pendingId;

    function _split(uint256 productId, address payee, uint32 share) internal override {
        if (_pendingId != productId) {
            if (_products[productId].splits.length != 0) revert ProductExists(productId);
            _pendingId = productId;
        }
        if (payee == address(0) || share == 0) revert BadSplit();
        _products[productId].splits.push(Split(payee, share));
    }

    function _product(uint256 productId, uint256 usdCents) internal override {
        _finish(productId, 0, usdCents, LICENCE_OFFSET + productId, true, true, 1_000);
    }

    function _finish(
        uint256 productId,
        uint256 price,
        uint256 usdCents,
        uint256 licenceId,
        bool active,
        bool oneLicencePerWallet,
        uint16 cashbackBps
    ) internal {
        Product storage p = _products[productId];
        uint256 n = p.splits.length;
        if (_pendingId != productId || n == 0 || n > MAX_PAYEES) revert BadSplit();
        uint256 sum;
        for (uint256 i = 0; i < n; ++i) sum += p.splits[i].share;
        if (sum != SHARE_DENOM) revert BadSplit();
        if (cashbackBps > MAX_CASHBACK_BPS) revert BadCashback();
        if (price == 0 && usdCents == 0) revert BadSplit();
        p.price = price;
        p.usdCents = usdCents;
        p.licenceId = licenceId;
        p.active = active;
        p.oneLicencePerWallet = oneLicencePerWallet;
        p.cashbackBps = cashbackBps;
        if (productId > lastProductId) lastProductId = productId;
        _pendingId = 0;
        emit ProductAdded(productId, usdCents, licenceId, n);
        emit CashbackSet(productId, cashbackBps);
    }

    /// Owner: add a brand-new release. Existing products can never be overwritten,
    /// and the shares set here are permanent too.
    /// @param shares parts per million of the payout (after cashback); must add up to 1,000,000
    function addProduct(
        uint256 productId,
        uint256 price,
        uint256 usdCents,
        uint256 licenceId,
        bool oneLicencePerWallet,
        uint16 cashbackBps,
        address[] calldata payees,
        uint32[] calldata shares
    ) external onlyOwner {
        if (productId == 0 || _products[productId].splits.length != 0) revert ProductExists(productId);
        if (payees.length != shares.length) revert BadSplit();
        for (uint256 i = 0; i < payees.length; ++i) _split(productId, payees[i], shares[i]);
        _finish(productId, price, usdCents, licenceId, true, oneLicencePerWallet, cashbackBps);
    }

    // --------------------------------------------------------------- pricing

    function _cumNow(IPancakePair p, bool use0) internal view returns (uint256 c) {
        c = use0 ? p.price0CumulativeLast() : p.price1CumulativeLast();
        (uint112 r0, uint112 r1, uint32 last) = p.getReserves();
        uint32 nowTs = uint32(block.timestamp);
        if (last != nowTs && r0 > 0 && r1 > 0) {
            unchecked {
                uint32 dt = nowTs - last;
                c += (use0 ? (uint256(r1) << 112) / r0 : (uint256(r0) << 112) / r1) * dt;
            }
        }
    }

    function _spot(IPancakePair p, bool use0) internal view returns (uint256) {
        (uint112 r0, uint112 r1, ) = p.getReserves();
        if (r0 == 0 || r1 == 0) revert NoPool();
        return use0 ? (uint256(r1) << 112) / r0 : (uint256(r0) << 112) / r1;
    }

    function _averages() internal view returns (uint256 avgP, uint256 avgU, bool fresh, uint256 cP, uint256 cU) {
        Twap memory t = twap;
        uint32 elapsed;
        unchecked { elapsed = uint32(block.timestamp) - t.ts; }
        if (elapsed >= TWAP_PERIOD) {
            cP = _cumNow(psykoPair, psykoIsToken0);
            cU = _cumNow(usdtPair, wbnbIsToken0);
            unchecked {
                avgP = uint224((cP - t.cumPsyko) / elapsed);
                avgU = uint224((cU - t.cumUsdt) / elapsed);
            }
            fresh = true;
        } else {
            avgP = t.avgPsyko;
            avgU = t.avgUsdt;
        }
    }

    function poke() public {
        (uint256 avgP, uint256 avgU, bool fresh, uint256 cP, uint256 cU) = _averages();
        if (fresh) twap = Twap(cP, cU, uint32(block.timestamp), uint224(avgP), uint224(avgU));
    }

    function psykoForUsdCents(uint256 cents) public view returns (uint256) {
        (uint256 avgP, uint256 avgU, , , ) = _averages();
        if (avgP == 0 || avgU == 0) revert PriceNotReady();
        uint256 p = Math.min(avgP, _spot(psykoPair, psykoIsToken0));
        uint256 u = Math.min(avgU, _spot(usdtPair, wbnbIsToken0));
        uint256 bnb = Math.mulDiv(cents * 1e16, Q112, u);
        return Math.mulDiv(bnb, Q112, p);
    }

    function _unitPrice(Product storage p) internal view returns (uint256) {
        return p.usdCents == 0 ? p.price : psykoForUsdCents(p.usdCents);
    }

    // ------------------------------------------------------------------ buy

    /// @param receiver  gets the licence AND the cashback (the payer, or a friend for a gift)
    function buy(
        uint256 productId,
        uint256 quantity,
        address receiver,
        uint256 maxTotal,
        bytes32 orderRef,
        Coupon calldata coupon,
        bytes calldata signature
    ) external nonReentrant whenNotPaused returns (uint256 paid) {
        Product storage p = _products[productId];
        if (!p.active) revert ProductInactive(productId);
        if (receiver == address(0)) revert ZeroAddress();
        if (quantity == 0) revert BadQuantity();
        if (p.licenceId != 0 && p.oneLicencePerWallet) {
            if (quantity != 1) revert BadQuantity();
            if (licence.balanceOf(receiver, p.licenceId) > 0) revert AlreadyOwned(productId);
        }

        if (p.usdCents != 0) poke();
        uint256 total = _unitPrice(p) * quantity;
        bytes32 couponHash;
        if (signature.length != 0) {
            couponHash = _useCoupon(productId, quantity, coupon, signature);
            total -= (total * coupon.discountBps) / BPS;
        }
        if (total > maxTotal) revert PriceAboveMax(total, maxTotal);

        _settle(p, productId, total, receiver);

        if (p.licenceId != 0) licence.mint(receiver, p.licenceId, p.oneLicencePerWallet ? 1 : quantity);

        emit Purchase(msg.sender, receiver, productId, quantity, total, couponHash, orderRef);
        return total;
    }

    function _settle(Product storage p, uint256 productId, uint256 total, address receiver) internal {
        uint256 cashback = (total * p.cashbackBps) / BPS;
        uint256 toPayees = total - cashback;
        if (toPayees > 0) {
            uint256 sent;
            uint256 n = p.splits.length;
            for (uint256 i = 0; i < n; ++i) {
                Split storage s = p.splits[i];
                uint256 part = (i == n - 1) ? toPayees - sent : (toPayees * s.share) / SHARE_DENOM;
                sent += part;
                if (part > 0) psyko.safeTransferFrom(msg.sender, s.payee, part);
            }
        }
        if (cashback > 0) {
            uint256 before = psyko.balanceOf(address(this));
            psyko.safeTransferFrom(msg.sender, address(this), cashback);
            uint256 received = psyko.balanceOf(address(this)) - before;
            uint64 start = uint64(block.timestamp);
            uint64 end = start + cashbackDuration;
            _grants[receiver].push(Grant(uint128(received), 0, start, end));
            totalCashbackOwed += received;
            emit CashbackGranted(receiver, productId, received, start, end);
        }
    }

    function quote(uint256 productId, uint256 quantity, Coupon calldata coupon, bytes calldata signature)
        external
        view
        returns (uint256 total, bool couponOk, uint256 cashback)
    {
        Product storage p = _products[productId];
        total = _unitPrice(p) * quantity;
        if (signature.length != 0) {
            couponOk = _couponValid(productId, quantity, coupon, signature);
            if (couponOk) total -= (total * coupon.discountBps) / BPS;
        }
        cashback = (total * p.cashbackBps) / BPS;
    }

    // --------------------------------------------------------------- cashback

    function _vested(Grant memory g) internal view returns (uint256) {
        if (block.timestamp >= g.end) return g.amount;
        if (block.timestamp <= g.start) return 0;
        return (uint256(g.amount) * (block.timestamp - g.start)) / (g.end - g.start);
    }

    /// Cashback the account can collect right now, plus totals for the website.
    function cashbackOf(address account)
        external
        view
        returns (uint256 claimable, uint256 totalGranted, uint256 totalClaimed, uint256 stillLocked)
    {
        Grant[] storage gs = _grants[account];
        for (uint256 i = 0; i < gs.length; ++i) {
            Grant memory g = gs[i];
            uint256 v = _vested(g);
            claimable += v - g.claimed;
            totalGranted += g.amount;
            totalClaimed += g.claimed;
            stillLocked += g.amount - v;
        }
    }

    function grantsOf(address account) external view returns (Grant[] memory) {
        return _grants[account];
    }

    /// Collect all cashback released so far. Works even while sales are paused.
    function claimCashback() external nonReentrant returns (uint256 amount) {
        Grant[] storage gs = _grants[msg.sender];
        uint256 i = firstOpenGrant[msg.sender];
        uint256 stop = Math.min(gs.length, i + MAX_CLAIM_BATCH);
        bool prefixDone = true;
        for (; i < stop; ++i) {
            Grant storage g = gs[i];
            uint256 v = _vested(g);
            uint256 due = v - g.claimed;
            if (due > 0) {
                g.claimed = uint128(v);
                amount += due;
            }
            if (prefixDone) {
                if (g.claimed == g.amount) firstOpenGrant[msg.sender] = i + 1;
                else prefixDone = false;
            }
        }
        if (amount == 0) revert NothingToClaim();
        totalCashbackOwed -= amount;
        psyko.safeTransfer(msg.sender, amount);
        emit CashbackClaimed(msg.sender, amount);
    }

    // --------------------------------------------------------------- coupons

    function couponDigest(Coupon calldata c) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(COUPON_TYPEHASH, c.productId, c.buyer, c.discountBps, c.maxUses, c.maxQuantity, c.deadline, c.salt))
        );
    }

    function _couponValid(uint256 productId, uint256 quantity, Coupon calldata c, bytes calldata sig) internal view returns (bool) {
        if (c.productId != productId || c.discountBps > BPS || quantity > c.maxQuantity) return false;
        if (c.buyer != address(0) && c.buyer != msg.sender) return false;
        if (block.timestamp > c.deadline) return false;
        bytes32 d = couponDigest(c);
        if (couponUses[d] >= c.maxUses) return false;
        return couponSigner != address(0) && SignatureChecker.isValidSignatureNow(couponSigner, d, sig);
    }

    function _useCoupon(uint256 productId, uint256 quantity, Coupon calldata c, bytes calldata sig) internal returns (bytes32 d) {
        if (c.productId != productId || c.discountBps > BPS) revert CouponInvalid();
        if (quantity > c.maxQuantity) revert CouponQuantity();
        if (c.buyer != address(0) && c.buyer != msg.sender) revert CouponInvalid();
        if (block.timestamp > c.deadline) revert CouponExpired();
        d = couponDigest(c);
        if (couponSigner == address(0) || !SignatureChecker.isValidSignatureNow(couponSigner, d, sig)) {
            revert CouponInvalid();
        }
        if (couponUses[d] >= c.maxUses) revert CouponUsedUp();
        unchecked { couponUses[d] += 1; }
    }

    // ------------------------------------------------------- payee addresses

    /// Owner: an artist changed wallets. Moves every share held by oldPayee to newPayee.
    /// Pass an empty productIds list to update the whole catalogue at once.
    /// Shares themselves never change.
    function replacePayee(address oldPayee, address newPayee, uint256[] calldata productIds) external onlyOwner {
        _replacePayee(oldPayee, newPayee, productIds);
    }

    /// A collaborator moves their own shares to a new wallet (sent from the old wallet).
    function changeMyPayeeAddress(address newPayee, uint256[] calldata productIds) external {
        _replacePayee(msg.sender, newPayee, productIds);
    }

    function _replacePayee(address oldPayee, address newPayee, uint256[] calldata productIds) internal {
        if (newPayee == address(0)) revert ZeroAddress();
        bool any;
        uint256 n = productIds.length == 0 ? lastProductId : productIds.length;
        for (uint256 k = 0; k < n; ++k) {
            uint256 id = productIds.length == 0 ? k + 1 : productIds[k];
            Split[] storage sp = _products[id].splits;
            for (uint256 i = 0; i < sp.length; ++i) {
                if (sp[i].payee == oldPayee) {
                    sp[i].payee = newPayee;
                    any = true;
                    emit PayeeChanged(id, oldPayee, newPayee);
                }
            }
        }
        if (!any) revert PayeeNotFound();
    }

    // ----------------------------------------------------------------- admin

    /// @param usdCents US cents per unit, e.g. 100 = $1.00 (0 = use the fixed PSYKO price)
    function setPrice(uint256 productId, uint256 price, uint256 usdCents) external onlyOwner {
        if (_products[productId].splits.length == 0) revert UnknownProduct(productId);
        if (price == 0 && usdCents == 0) revert BadSplit();
        _products[productId].price = price;
        _products[productId].usdCents = usdCents;
        emit PriceSet(productId, price, usdCents);
    }

    function setActive(uint256 productId, bool active) external onlyOwner {
        if (_products[productId].splits.length == 0) revert UnknownProduct(productId);
        _products[productId].active = active;
        emit ActiveSet(productId, active);
    }

    /// Share of each future sale returned to the buyer (1000 = 10%).
    function setCashback(uint256 productId, uint16 cashbackBps) external onlyOwner {
        if (_products[productId].splits.length == 0) revert UnknownProduct(productId);
        if (cashbackBps > MAX_CASHBACK_BPS) revert BadCashback();
        _products[productId].cashbackBps = cashbackBps;
        emit CashbackSet(productId, cashbackBps);
    }

    /// Applies to future purchases only; cashback already granted keeps its own schedule.
    function setCashbackDuration(uint32 duration) external onlyOwner {
        if (duration < MIN_CASHBACK_DURATION || duration > MAX_CASHBACK_DURATION) revert BadCashback();
        cashbackDuration = duration;
        emit CashbackDurationSet(duration);
    }

    function setCouponSigner(address signer) external onlyOwner {
        couponSigner = signer;
        emit CouponSignerSet(signer);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// Returns tokens sent here by mistake. Buyers' set-aside cashback can never be taken.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(psyko) && psyko.balanceOf(address(this)) - amount < totalCashbackOwed) {
            revert EscrowProtected();
        }
        token.safeTransfer(to, amount);
    }

    // ------------------------------------------------------------------ views

    function product(uint256 productId)
        external
        view
        returns (
            uint256 price,
            uint256 usdCents,
            uint256 licenceId,
            bool active,
            bool oneLicencePerWallet,
            uint16 cashbackBps,
            address[] memory payees,
            uint32[] memory shares
        )
    {
        Product storage p = _products[productId];
        uint256 n = p.splits.length;
        payees = new address[](n);
        shares = new uint32[](n);
        for (uint256 i = 0; i < n; ++i) {
            payees[i] = p.splits[i].payee;
            shares[i] = p.splits[i].share;
        }
        return (p.price, p.usdCents, p.licenceId, p.active, p.oneLicencePerWallet, p.cashbackBps, payees, shares);
    }

    /// Every product a wallet is paid from, for an artist checking their shares.
    function productsOf(address payee) external view returns (uint256[] memory ids, uint32[] memory shares) {
        uint256 count;
        for (uint256 id = 1; id <= lastProductId; ++id) {
            Split[] storage sp = _products[id].splits;
            for (uint256 i = 0; i < sp.length; ++i) if (sp[i].payee == payee) ++count;
        }
        ids = new uint256[](count);
        shares = new uint32[](count);
        uint256 k;
        for (uint256 id = 1; id <= lastProductId; ++id) {
            Split[] storage sp = _products[id].splits;
            for (uint256 i = 0; i < sp.length; ++i) {
                if (sp[i].payee == payee) {
                    ids[k] = id;
                    shares[k] = sp[i].share;
                    ++k;
                }
            }
        }
    }
}
