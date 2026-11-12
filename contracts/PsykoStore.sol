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

contract PsykoStore is Ownable2Step, Pausable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_PAYEES = 8;

    struct Product {
        uint256 price;
        uint256 usdCents;
        uint256 licenceId;
        bool active;
        bool oneLicencePerWallet;
        address[] payees;
        uint16[] shares;
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
    mapping(uint256 => Product) private _products;
    mapping(bytes32 => uint32) public couponUses;

    event ProductSet(uint256 indexed productId, uint256 price, uint256 licenceId, bool active);
    event CouponSignerSet(address signer);
    event Purchase(
        address indexed payer,
        address indexed receiver,
        uint256 indexed productId,
        uint256 quantity,
        uint256 paid,
        bytes32 couponHash,
        bytes32 orderRef
    );

    error ProductInactive(uint256 productId);
    error AlreadyOwned(uint256 productId);
    error PriceAboveMax(uint256 total, uint256 maxTotal);
    error BadSplit();
    error BadQuantity();
    error CouponInvalid();
    error CouponExpired();
    error CouponUsedUp();
    error CouponQuantity();
    error ZeroAddress();
    error NoPool();
    error PriceNotReady();

    constructor(
        IERC20 psyko_,
        IPsykoLicense licence_,
        address couponSigner_,
        address initialOwner,
        IPancakeFactory factory,
        address wbnb,
        address usdt
    ) Ownable(initialOwner) EIP712("PsykoStore", "1") {
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
    }

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

        if (total > 0) {
            uint256 sent;
            uint256 n = p.payees.length;
            for (uint256 i = 0; i < n; ++i) {
                uint256 part = (i == n - 1) ? total - sent : (total * p.shares[i]) / BPS;
                sent += part;
                if (part > 0) psyko.safeTransferFrom(msg.sender, p.payees[i], part);
            }
        }

        if (p.licenceId != 0) licence.mint(receiver, p.licenceId, p.oneLicencePerWallet ? 1 : quantity);

        emit Purchase(msg.sender, receiver, productId, quantity, total, couponHash, orderRef);
        return total;
    }

    function quote(uint256 productId, uint256 quantity, Coupon calldata coupon, bytes calldata signature)
        external
        view
        returns (uint256 total, bool couponOk)
    {
        Product storage p = _products[productId];
        total = _unitPrice(p) * quantity;
        if (signature.length != 0) {
            couponOk = _couponValid(productId, quantity, coupon, signature);
            if (couponOk) total -= (total * coupon.discountBps) / BPS;
        }
    }

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

    function setProduct(
        uint256 productId,
        uint256 price,
        uint256 usdCents,
        uint256 licenceId,
        bool active,
        bool oneLicencePerWallet,
        address[] calldata payees,
        uint16[] calldata shares
    ) external onlyOwner {
        uint256 n = payees.length;
        if (n == 0 || n > MAX_PAYEES || n != shares.length) revert BadSplit();
        uint256 sum;
        for (uint256 i = 0; i < n; ++i) {
            if (payees[i] == address(0)) revert ZeroAddress();
            sum += shares[i];
        }
        if (sum != BPS) revert BadSplit();
        Product storage p = _products[productId];
        p.price = price;
        p.usdCents = usdCents;
        p.licenceId = licenceId;
        p.active = active;
        p.oneLicencePerWallet = oneLicencePerWallet;
        p.payees = payees;
        p.shares = shares;
        emit ProductSet(productId, price, licenceId, active);
    }

    function setActive(uint256 productId, bool active) external onlyOwner {
        _products[productId].active = active;
        emit ProductSet(productId, _products[productId].price, _products[productId].licenceId, active);
    }

    function setCouponSigner(address signer) external onlyOwner {
        couponSigner = signer;
        emit CouponSignerSet(signer);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function product(uint256 productId)
        external
        view
        returns (
            uint256 price,
            uint256 usdCents,
            uint256 licenceId,
            bool active,
            bool oneLicencePerWallet,
            address[] memory payees,
            uint16[] memory shares
        )
    {
        Product storage p = _products[productId];
        return (p.price, p.usdCents, p.licenceId, p.active, p.oneLicencePerWallet, p.payees, p.shares);
    }
}
