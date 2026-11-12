# PSYKO Creator Commerce Kit

An open-source checkout for independent artists and developers on BNB Smart Chain. A creator can sell music, software licences, event tickets and bookable services for a BEP-20 token. Buyers pay from their own wallet, and the money goes straight to the creator and collaborators. A wallet signature then unlocks downloads, with no accounts and no passwords.

It runs in production at [psykovsky.com](https://psykovsky.com) for the PSYKO token.

## What is in the kit

| Part | What it does |
|---|---|
| `contracts/PsykoLicense.sol` | ERC-1155 licence token, one id per product. Licences are non-transferable unless resale is switched on for that id. Only the holder can burn a licence; the owner cannot take one away. |
| `contracts/PsykoStore.sol` | One checkout for every product. Pays each collaborator directly from the buyer (up to 8 payees, shares in basis points), mints the licence, and emits a `Purchase` receipt. Prices can be fixed in tokens or set in US dollars. Dollar prices are converted with the lower of the live PancakeSwap price and a 15-minute average, which resists price manipulation. Signed discount coupons (EIP-712) are supported. |
| `contracts/PsykoStoreV3.sol` + `PsykoCatalogue.sol` | A catalogue store for music: every album and song is written into the contract with its collaborators and their shares, which can never be changed (only a payee's wallet address can move). Part of each price returns to the buyer as cashback in the creator's token, set aside at the moment of sale and released linearly over 90 days. The owner cannot withdraw set-aside cashback, and pausing sales never blocks claims. Same USD pricing (live price vs. 15-minute average) and EIP-712 coupons as PsykoStore. |
| `contracts/PsykoZap.sol` | Pay with BNB or any BEP-20 token: it swaps to PSYKO and buys in one transaction, and returns any leftover PSYKO to the buyer. It also takes cross-chain payments from Solana through a deBridge hook; if a bridged purchase cannot complete, the delivered tokens are refunded on BNB Chain. It has no owner, no admin and no fees. |
| `gate/` | PHP download gate, "sign in with your wallet to download". It issues a readable EIP-712 challenge that can be used once, recovers the signer with the chain's `ecrecover` precompile, checks the licence balance on two RPC providers that must agree, and returns a signed download link that expires after 5 minutes and can be opened at most 3 times. Files can sit in a folder outside the web root or in a private S3-compatible bucket (for example Cloudflare R2); for bucket files the gate redirects to a presigned link that expires within minutes, so nothing can be downloaded without a licence. It needs only `curl` and `json`. `booking712.php` records paid bookings and tickets only after checking the payment on chain. |
| `js/src/` | Browser libraries: wallet discovery (EIP-6963), checkout, payment with any token, Solana checkout, download sign-in, booking and tickets. Minified builds are in `js/dist/`. |

## Deployed contracts (BNB Smart Chain, chain id 56)

All sources are verified on [Sourcify](https://sourcify.dev); compiled with solc 0.8.24, optimizer 200 runs, EVM version shanghai, OpenZeppelin Contracts 5.1.0.

| Contract | Address |
|---|---|
| PsykoLicense | [`0x2Bdf3cB9138F3Ef71DD6A83aB24eA25DD540B974`](https://repo.sourcify.dev/56/0x2Bdf3cB9138F3Ef71DD6A83aB24eA25DD540B974) |
| PsykoStore | [`0x64f2CddD7Fd2D8E2FFe8Dfe99B30A95678D63c10`](https://repo.sourcify.dev/56/0x64f2CddD7Fd2D8E2FFe8Dfe99B30A95678D63c10) |
| PsykoStoreV3 | [`0x03878fD227126F459Cf7C2eC91029d01bCd1962E`](https://repo.sourcify.dev/56/0x03878fD227126F459Cf7C2eC91029d01bCd1962E) |
| PsykoZap | [`0xFC712Ea8a53A2a824Bc404B2374d2663E09d0174`](https://repo.sourcify.dev/56/0xFC712Ea8a53A2a824Bc404B2374d2663E09d0174) |
| PSYKO token (BEP-20) | [`0xaaD978c2155FAccF64b93A8D2B8A5D8f2317D308`](https://repo.sourcify.dev/56/0xaaD978c2155FAccF64b93A8D2B8A5D8f2317D308) |

## Owner powers, stated openly

- **PSYKO token:** the PSYKO token owner retains a blacklist function. It has been used only against sandwich attacks on buyers, during three episodes between February and April 2024, to block 11 addresses: 9 bot contracts and 2 wallets that took part in the attacks. Holding limits are disabled. No other restrictions are active.

  | Blocked address | Type | Date | Blacklist transaction |
  |---|---|---|---|
  | [`0x511aaacd5410eb908d0ad0eb9f25190da4ab84c6`](https://bscscan.com/address/0x511aaacd5410eb908d0ad0eb9f25190da4ab84c6) | contract | 18 Feb 2024 | [`0x2a13dd61…`](https://bscscan.com/tx/0x2a13dd613ecb979f11d06f0066bda6128ccade91b3efa8650d8dc309c9b59c1f) |
  | [`0x0000000c6e715f038b33a8c99e0be1c8db24d70b`](https://bscscan.com/address/0x0000000c6e715f038b33a8c99e0be1c8db24d70b) | contract | 21 Feb 2024 | [`0x6bd6056e…`](https://bscscan.com/tx/0x6bd6056e3550531f49dea38d039bc61e7f52b6286efb423df7fa843cb92fe427) |
  | [`0x89c050cd95c73a9354fcf02dca36e70d3cc8d200`](https://bscscan.com/address/0x89c050cd95c73a9354fcf02dca36e70d3cc8d200) | contract | 21 Feb 2024 | [`0xfd063398…`](https://bscscan.com/tx/0xfd063398b19f4fa0fcce684c54c5a47d6bf55dd804e29d072c96d517e4820808) |
  | [`0x000000000d73c899c2234737da01d5fe620fd603`](https://bscscan.com/address/0x000000000d73c899c2234737da01d5fe620fd603) | contract | 21 Feb 2024 | [`0xae42ca81…`](https://bscscan.com/tx/0xae42ca815017ede5b482dcc74706fdb20991ae282f09c65086622241266b63b0) |
  | [`0x000000000000d43e334f64e2ae7a8cf488f9ca91`](https://bscscan.com/address/0x000000000000d43e334f64e2ae7a8cf488f9ca91) | contract | 21 Feb 2024 | [`0x6ae1b8dc…`](https://bscscan.com/tx/0x6ae1b8dca60e6f6ecf697ec865b01b54f6db45437d61676f3742fdbf40b13838) |
  | [`0x77e4cbbc378b1839319af305ad4b4765129430ba`](https://bscscan.com/address/0x77e4cbbc378b1839319af305ad4b4765129430ba) | wallet | 23 Mar 2024 | [`0xa4a09194…`](https://bscscan.com/tx/0xa4a09194574fc4ded69965edfa33ed1408a58e55b364171a9e1d1248cad79536) |
  | [`0x54d294cc0000cfb5426e2ec43349b953d13e2700`](https://bscscan.com/address/0x54d294cc0000cfb5426e2ec43349b953d13e2700) | contract | 23 Mar 2024 | [`0xd3309034…`](https://bscscan.com/tx/0xd3309034c630a600743a70d5088505e2682dcdd8f1d0b6935837088cd134750b) |
  | [`0x9fb74dddbb0f4a0f997d0c81a6028b39c1acf54d`](https://bscscan.com/address/0x9fb74dddbb0f4a0f997d0c81a6028b39c1acf54d) | contract | 15 Apr 2024 | [`0x9b921cb8…`](https://bscscan.com/tx/0x9b921cb8ddf64a14f8bfba09c54ca5ca773c4a33c6d927593b5f2614326105fd) |
  | [`0x555555595d6f1433bc5cf71e91e106a734881121`](https://bscscan.com/address/0x555555595d6f1433bc5cf71e91e106a734881121) | contract | 16 Apr 2024 | [`0x8093beb7…`](https://bscscan.com/tx/0x8093beb71488e9d7acfe9e6b9e6c699eca5d5587dbb1eb86287e585beedd23b2) |
  | [`0x6827ab5b01b02a594d9d36f2ffa787f6c7c5a72d`](https://bscscan.com/address/0x6827ab5b01b02a594d9d36f2ffa787f6c7c5a72d) | contract | 16 Apr 2024 | [`0x086baf24…`](https://bscscan.com/tx/0x086baf24ba5da29d0cefd0d273873f4e4d6b708a94268f138a83cee7c8a17c66) |
  | [`0x8412508cc17913691627629d6fcdd5bb58a1e461`](https://bscscan.com/address/0x8412508cc17913691627629d6fcdd5bb58a1e461) | wallet | 16 Apr 2024 | [`0xbd2de53e…`](https://bscscan.com/tx/0xbd2de53ed5fe8f9a620e8e76bd70cf79b2ffc793f43ed1449fafa860a7ffa62a) |

- **PsykoStore:** the owner can add or change products, prices and payee splits; switch products on or off; pause sales; and set the coupon signer. The store never holds buyer funds.
- **PsykoStoreV3:** the owner can add new products (new ids only), change prices, switch products on or off, set the cashback rate per product (at most 50%) and the release period (at most 365 days), pause sales, set the coupon signer, and move a payee's wallet address (a payee can also move their own). The owner cannot change any product's collaborators or shares, and cannot withdraw cashback that is owed to buyers.
- **PsykoLicense:** the owner can choose which contracts may mint, switch resale on for a licence id, and set metadata. The owner cannot burn or move anyone's licence.
- **PsykoZap:** none. It has no owner.

## Setting up the gate

1. Copy `gate/gate_config.example.php` to a private folder outside the web root (for example `/home/USER/psyko_private/gate_config.php`) and fill it in.
2. In `gate/`, create `gate_config.php` with one line that loads it: `<?php require '/home/USER/psyko_private/gate_config.php';`. Copy `gate/gate_codes.example.php` to `gate/gate_codes.php` for coupon codes. Both files are in `.gitignore`: never commit them.
3. Keep the download files and the `gate_nonces` folder outside the public web root, or put the files in a private bucket and fill in `GATE_S3` with a read-only key.
4. `GATE_SECRET` signs download links. Use a long random value and keep it private.
5. Keep `gate/.htaccess`: it allows only the five endpoints and denies every other file in the folder.

## Licence

MIT. See [LICENSE](LICENSE).
