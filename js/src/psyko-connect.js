(() => {
  "use strict";
  const CFG = {
    chainId: 56,
    chainHex: "0x38",
    psyko: "0xaaD978c2155FAccF64b93A8D2B8A5D8f2317D308",
    store: "0x64f2CddD7Fd2D8E2FFe8Dfe99B30A95678D63c10",
    licence: "0x2Bdf3cB9138F3Ef71DD6A83aB24eA25DD540B974",
    zap: "0xFC712Ea8a53A2a824Bc404B2374d2663E09d0174",
    router: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
    wbnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
    payTokens: [ {
      symbol: "BNB",
      address: "BNB"
    }, {
      symbol: "USDT",
      address: "0x55d398326f99059fF775485246999027B3197955"
    }, {
      symbol: "ETH",
      address: "0x2170Ed0880ac9A755fd29B2688956BD959F933F8"
    }, {
      symbol: "USDC",
      address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"
    } ],
    solana: {
      enabled: true,
      api: "https://dln.debridge.finance/v1.0",
      chainId: 7565164,
      sol: "11111111111111111111111111111111",
      usdc: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
      usdtBsc: "0x55d398326f99059fF775485246999027B3197955",
      hookGas: 1e6,
      web3: "https://unpkg.com/@solana/web3.js@1.98.4/lib/index.iife.min.js"
    },
    gateBase: "/gate/",
    walletApk: "https://psykovsky.com/apk/PSYKO-Wallet.apk"
  };
  const found = new Map;
  window.addEventListener("eip6963:announceProvider", e => {
    const d = e.detail;
    if (d && d.info && d.provider && d.info.uuid) found.set(d.info.uuid, d);
  });
  const ask = () => window.dispatchEvent(new Event("eip6963:requestProvider"));
  ask();
  let current = null;
  function css() {
    if (document.getElementById("pc-style")) return;
    const s = document.createElement("style");
    s.id = "pc-style";
    s.textContent = `\n      .pc-veil{position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;background:rgba(5,7,13,.72);backdrop-filter:blur(6px)}\n      .pc-box{width:min(360px,calc(100vw - 32px));padding:18px;border-radius:16px;background:linear-gradient(160deg,#121629,#0a0d1a);\n        box-shadow:inset 0 0 0 .7px rgba(176,102,240,.45),0 20px 60px rgba(0,0,0,.6);color:#dce8f8;font:13px/1.45 "Share Tech Mono",ui-monospace,monospace}\n      .pc-box h3{margin:0 0 12px;font:600 13px/1 "Orbitron",sans-serif;letter-spacing:.14em;text-transform:uppercase;color:#dc5ce6}\n      .pc-w{display:flex;align-items:center;gap:12px;width:100%;margin:6px 0;padding:10px 12px;border:0;border-radius:11px;cursor:pointer;color:inherit;font:inherit;text-align:left;\n        background:rgba(255,255,255,.035);box-shadow:inset 0 0 0 .7px rgba(90,220,240,.25)}\n      .pc-w:hover{box-shadow:inset 0 0 0 .7px rgba(90,220,240,.7)}\n      .pc-w img{width:28px;height:28px;border-radius:7px}\n      .pc-w small{display:block;color:#7f8bb0;font-size:11px}\n      .pc-note{margin:10px 0 0;color:#7f8bb0;font-size:11.5px}\n      .pc-note a{color:#5adcf0}\n      .pc-w[disabled]{opacity:.45;cursor:default}\n      .pc-status{margin:10px 0 0;padding:8px 10px;border-radius:9px;background:rgba(90,220,240,.06);font-size:12px;white-space:pre-line}\n      .pc-status.err{background:rgba(240,90,120,.1);color:#ff9fb4}\n      .pc-x{float:right;border:0;background:none;color:#7f8bb0;font-size:18px;cursor:pointer;line-height:1}`;
    document.head.appendChild(s);
  }
  const escHtml = s => String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[c]));
  function pick() {
    return new Promise((resolve, reject) => {
      ask();
      setTimeout(() => {
        const list = [ ...found.values() ];
        if (!list.length && window.ethereum) list.push({
          info: {
            uuid: "legacy",
            name: window.ethereum.isPsykoWallet ? "PSYKO Wallet" : "Browser wallet",
            icon: "",
            rdns: ""
          },
          provider: window.ethereum
        });
        if (list.length === 1) return resolve(list[0]);
        list.sort((a, b) => (b.info.rdns === "com.psykovsky.wallet") - (a.info.rdns === "com.psykovsky.wallet"));
        css();
        const veil = document.createElement("div");
        veil.className = "pc-veil";
        veil.innerHTML = `<div class="pc-box" role="dialog" aria-label="Choose a wallet"><button class="pc-x" aria-label="Close">×</button><h3>Connect a wallet</h3>\n          ${list.map((w, i) => `<button class="pc-w" data-i="${i}">${w.info.icon ? `<img src="${escHtml(w.info.icon)}" alt="">` : ""}<span>${escHtml(w.info.name)}<small>${w.info.rdns === "com.psykovsky.wallet" ? "recommended for PSYKO" : escHtml(w.info.rdns || "")}</small></span></button>`).join("")}\n          ${list.length ? "" : `<p class="pc-note">No wallet found in this browser. On Android, get <a href="${escHtml(CFG.walletApk)}">PSYKO Wallet</a> and open this page from its Stores tab.</p>`}\n          <p class="pc-note">Your keys stay in your wallet. This site only sees your address after you approve.</p></div>`;
        document.body.appendChild(veil);
        const close = err => {
          veil.remove();
          if (err) reject(err);
        };
        veil.querySelector(".pc-x").onclick = () => close(Object.assign(new Error("Cancelled."), {
          code: 4001
        }));
        veil.onclick = e => {
          if (e.target === veil) close(Object.assign(new Error("Cancelled."), {
            code: 4001
          }));
        };
        veil.querySelectorAll(".pc-w").forEach(b => b.onclick = () => {
          veil.remove();
          resolve(list[Number(b.dataset.i)]);
        });
      }, 120);
    });
  }
  async function ensureBsc(provider) {
    const id = await provider.request({
      method: "eth_chainId"
    });
    if (String(id).toLowerCase() === CFG.chainHex) return;
    try {
      await provider.request({
        method: "wallet_switchEthereumChain",
        params: [ {
          chainId: CFG.chainHex
        } ]
      });
    } catch (e) {
      if (e && e.code === 4902) {
        await provider.request({
          method: "wallet_addEthereumChain",
          params: [ {
            chainId: CFG.chainHex,
            chainName: "BNB Smart Chain",
            nativeCurrency: {
              name: "BNB",
              symbol: "BNB",
              decimals: 18
            },
            rpcUrls: [ "https://bsc-dataseed.bnbchain.org" ],
            blockExplorerUrls: [ "https://bscscan.com" ]
          } ]
        });
      } else throw e;
    }
  }
  async function connect() {
    if (current) return current;
    const w = await pick();
    const [account] = await w.provider.request({
      method: "eth_requestAccounts"
    });
    await ensureBsc(w.provider);
    current = {
      provider: w.provider,
      info: w.info,
      account: account
    };
    w.provider.on && w.provider.on("accountsChanged", a => {
      if (current) current.account = a && a[0];
      if (!a || !a.length) current = null;
    });
    return current;
  }
  const word = hexNoPrefix => hexNoPrefix.padStart(64, "0");
  const uint = v => word(BigInt(v).toString(16));
  const addr = a => {
    if (!/^0x[0-9a-fA-F]{40}$/.test(a)) throw new Error("Bad address " + a);
    return word(a.slice(2).toLowerCase());
  };
  const b32 = h => {
    const x = String(h || "0x").slice(2);
    if (x.length > 64) throw new Error("bytes32 too long");
    return x.padEnd(64, "0");
  };
  const bytesTail = h => {
    const x = String(h || "0x").slice(2);
    const n = x.length / 2;
    return uint(n) + (n ? x.padEnd(Math.ceil(n / 32) * 64, "0") : "");
  };
  const NO_COUPON = {
    productId: 0,
    buyer: "0x0000000000000000000000000000000000000000",
    discountBps: 0,
    maxUses: 0,
    maxQuantity: 0,
    deadline: 0,
    salt: "0x",
    signature: "0x"
  };
  const tuple = c => uint(c.productId) + addr(c.buyer) + uint(c.discountBps) + uint(c.maxUses) + uint(c.maxQuantity || 0) + uint(c.deadline) + b32(c.salt);
  async function call(to, data) {
    const r = await current.provider.request({
      method: "eth_call",
      params: [ {
        from: current.account,
        to: to,
        data: data
      }, "latest" ]
    });
    return String(r).slice(2);
  }
  async function waitTx(hash) {
    for (let i = 0; i < 120; i++) {
      const r = await current.provider.request({
        method: "eth_getTransactionReceipt",
        params: [ hash ]
      });
      if (r) {
        if (r.status !== "0x1") throw new Error("The transaction failed on-chain.");
        return r;
      }
      await new Promise(s => setTimeout(s, 1e3));
    }
    throw new Error("Still waiting for the network. Check your wallet's activity.");
  }
  async function quote(productId, quantity = 1, coupon = NO_COUPON) {
    const data = "0x774cbd36" + uint(productId) + uint(quantity) + tuple(coupon) + uint(10 * 32) + bytesTail(coupon.signature);
    const r = await call(CFG.store, data);
    return {
      total: BigInt("0x" + r.slice(0, 64)),
      couponOk: BigInt("0x" + r.slice(64, 128)) === 1n
    };
  }
  function couponFromUrl() {
    const c = new URLSearchParams(location.search).get("c");
    if (!c) return null;
    try {
      const j = JSON.parse(atob(c.replace(/-/g, "+").replace(/_/g, "/")));
      return {
        ...j,
        signature: j.signature
      };
    } catch (_) {
      return null;
    }
  }
  async function buy(opts) {
    if (!CFG.store) throw new Error("Store address not set in psyko-connect.js");
    const w = await connect();
    const quantity = opts.quantity || 1;
    const coupon = opts.coupon || couponFromUrl() || NO_COUPON;
    const {total: total, couponOk: couponOk} = await quote(opts.productId, quantity, coupon);
    if (coupon !== NO_COUPON && !couponOk) throw new Error("This coupon is not valid here (wrong product, wallet or quantity, expired, or used up). Nothing was charged.");
    const useCoupon = coupon;
    const price = total + total * 15n / 1000n;
    if (price > 0n) {
      await ensureBsc(w.provider);
      const allowed = BigInt("0x" + await call(CFG.psyko, "0xdd62ed3e" + addr(w.account) + addr(CFG.store)));
      if (allowed < price) {
        const h = await w.provider.request({
          method: "eth_sendTransaction",
          params: [ {
            from: w.account,
            to: CFG.psyko,
            data: "0x095ea7b3" + addr(CFG.store) + uint(price)
          } ]
        });
        await waitTx(h);
      }
    }
    const data = "0x019437d6" + uint(opts.productId) + uint(quantity) + addr(opts.receiver || w.account) + uint(price) + b32(opts.orderRef || "0x") + tuple(useCoupon) + uint(13 * 32) + bytesTail(useCoupon.signature);
    await ensureBsc(w.provider);
    const hash = await w.provider.request({
      method: "eth_sendTransaction",
      params: [ {
        from: w.account,
        to: CFG.store,
        data: data
      } ]
    });
    await waitTx(hash);
    return {
      hash: hash,
      quoted: total,
      maxPaid: price,
      couponUsed: useCoupon !== NO_COUPON
    };
  }
  async function hasLicence(id, account) {
    const a = account || (await connect()).account;
    return BigInt("0x" + await call(CFG.licence, "0x00fdd58e" + addr(a) + uint(id))) > 0n;
  }
  async function downloadSignIn(licenceId, purpose) {
    const w = await connect();
    await ensureBsc(w.provider);
    const ch = await fetch(CFG.gateBase + "challenge712.php", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        wallet: w.account,
        licence: licenceId,
        purpose: purpose
      })
    }).then(r => r.json());
    if (!ch.ok) throw new Error(ch.error || "Could not start sign-in.");
    const sig = await w.provider.request({
      method: "eth_signTypedData_v4",
      params: [ w.account, JSON.stringify(ch.typedData) ]
    });
    const res = await fetch(CFG.gateBase + "redeem712.php", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        nonce: ch.typedData.message.nonce,
        signature: sig
      })
    }).then(r => r.json());
    if (!res.ok) throw new Error(res.error || "Sign-in failed.");
    return res;
  }
  const fmt = (wei, dp = 2) => {
    const s = Number(BigInt(wei) / 10n ** 12n) / 1e6;
    return s.toLocaleString("en-US", {
      maximumFractionDigits: dp
    });
  };
  const arr = addrs => uint(addrs.length) + addrs.map(addr).join("");
  async function psykoForUsd(cents) {
    return BigInt("0x" + (await call(CFG.store, "0x2b5dd743" + uint(cents))).slice(0, 64));
  }
  async function amountIn(out, path) {
    const r = await call(CFG.router, "0x1f00ca74" + uint(out) + uint(64) + arr(path));
    return BigInt("0x" + r.slice(64 * 2, 64 * 3));
  }
  const pathFor = t => t === "BNB" ? [ CFG.wbnb, CFG.psyko ] : [ t, CFG.wbnb, CFG.psyko ];
  async function quoteAny(opts, token) {
    const quantity = opts.quantity || 1;
    const storePrice = (await quote(opts.productId, quantity)).total;
    let target = opts.usdCents ? await psykoForUsd(opts.usdCents) : storePrice * (10000n + BigInt(opts.bonusBps || 1200)) / 10000n;
    if (target < storePrice * 1015n / 1000n) target = storePrice * 1015n / 1000n;
    const need = await amountIn(target, pathFor(token)) * 1003n / 1000n;
    return {
      token: token,
      need: need,
      target: target,
      storePrice: storePrice,
      bonus: target - storePrice
    };
  }
  async function payWithAny(opts, token) {
    if (!CFG.zap) throw new Error("This payment option is not active yet.");
    const w = await connect();
    await ensureBsc(w.provider);
    const q = await quoteAny(opts, token);
    const receiver = opts.receiver || w.account;
    const deadline = Math.floor(Date.now() / 1e3) + 15 * 60;
    const order = uint(opts.productId) + uint(opts.quantity || 1) + addr(receiver) + uint(q.storePrice + q.bonus * 9n / 10n) + b32(opts.orderRef || "0x") + uint(deadline);
    let hash;
    if (token === "BNB") {
      hash = await w.provider.request({
        method: "eth_sendTransaction",
        params: [ {
          from: w.account,
          to: CFG.zap,
          value: "0x" + q.need.toString(16),
          data: "0x2c48538b" + order
        } ]
      });
    } else {
      const bal = BigInt("0x" + await call(token, "0x70a08231" + addr(w.account)));
      if (bal < q.need) throw new Error("Not enough balance for this payment. You need " + fmt(q.need, 4) + ".");
      const allowed = BigInt("0x" + await call(token, "0xdd62ed3e" + addr(w.account) + addr(CFG.zap)));
      if (allowed < q.need) {
        const h = await w.provider.request({
          method: "eth_sendTransaction",
          params: [ {
            from: w.account,
            to: token,
            data: "0x095ea7b3" + addr(CFG.zap) + uint(q.need)
          } ]
        });
        await waitTx(h);
      }
      const path = pathFor(token);
      hash = await w.provider.request({
        method: "eth_sendTransaction",
        params: [ {
          from: w.account,
          to: CFG.zap,
          data: "0x10f19dcf" + uint(q.need) + uint(8 * 32) + order + arr(path)
        } ]
      });
    }
    await waitTx(hash);
    return {
      hash: hash,
      quoted: q.storePrice,
      bonus: q.bonus,
      paidWith: token
    };
  }
  async function choosePayment(opts) {
    const w = await connect();
    css();
    const veil = document.createElement("div");
    veil.className = "pc-veil";
    const rows = [ `<button class="pc-w" data-t="PSYKO"><span>Pay with PSYKO · <b>$${opts.usdPsyko}</b><small>from your PSYKO balance</small></span></button>` ].concat(CFG.zap ? CFG.payTokens.map(t => `<button class="pc-w" data-t="${t.address}"><span>Pay with ${t.symbol} · <b>$${opts.usdOther}</b><small data-q="${t.address}">working out the bonus…</small></span></button>`) : []).concat(CFG.zap && opts.solana && SOLCFG.enabled ? [ `<button class="pc-w" data-t="SOLANA"><span>Pay from Solana (SOL / USDC) · <b>$${opts.usdOther}</b><small>bridged to BNB Chain for you · smaller bonus (bridge fee)</small></span></button>` ] : []);
    veil.innerHTML = `<div class="pc-box" role="dialog" aria-label="Choose how to pay"><button class="pc-x" aria-label="Close">×</button><h3>${escHtml(opts.label || "Checkout")}</h3>${rows.join("")}\n      <p class="pc-note">Paying with another coin buys PSYKO for you in the same transaction: the licence is paid in PSYKO and the PSYKO left over goes to your wallet.</p></div>`;
    document.body.appendChild(veil);
    if (CFG.zap) CFG.payTokens.forEach(async t => {
      const el = veil.querySelector(`[data-q="${t.address}"]`);
      try {
        const q = await quoteAny({
          productId: opts.productId,
          quantity: opts.quantity,
          usdCents: opts.usdOther * 100
        }, t.address);
        el.textContent = "≈ " + fmt(q.need, t.symbol === "BNB" || t.symbol === "ETH" ? 5 : 2) + " " + t.symbol + " · you also get ≈ " + fmt(q.bonus, 0) + " PSYKO";
      } catch (e) {
        el.textContent = "not available right now";
      }
    });
    return new Promise((resolve, reject) => {
      const close = err => {
        veil.remove();
        if (err) reject(err);
      };
      veil.querySelector(".pc-x").onclick = () => close(Object.assign(new Error("Cancelled."), {
        code: 4001
      }));
      veil.onclick = e => {
        if (e.target === veil) close(Object.assign(new Error("Cancelled."), {
          code: 4001
        }));
      };
      veil.querySelectorAll(".pc-w").forEach(b => b.onclick = () => {
        veil.remove();
        resolve(b.dataset.t);
      });
    });
  }
  const SOLCFG = CFG.solana;
  const solWallets = () => {
    const out = [], seen = new Set;
    const add = (name, p) => {
      if (p && !seen.has(p) && (p.signAndSendTransaction || p.request)) {
        seen.add(p);
        out.push({
          name: name,
          provider: p
        });
      }
    };
    add("Phantom", window.phantom && window.phantom.solana);
    add("Solflare", window.solflare);
    add("Backpack", window.backpack && (window.backpack.solana || window.backpack));
    if (!out.length) add("Solana wallet", window.solana);
    return out;
  };
  let web3Loading = null;
  const loadWeb3 = () => window.solanaWeb3 ? Promise.resolve(window.solanaWeb3) : web3Loading = web3Loading || new Promise((ok, bad) => {
    const sc = document.createElement("script");
    sc.src = SOLCFG.web3;
    sc.crossOrigin = "anonymous";
    sc.onload = () => window.solanaWeb3 ? ok(window.solanaWeb3) : bad(new Error("Solana module failed to load."));
    sc.onerror = () => {
      web3Loading = null;
      bad(new Error("Solana module failed to load. Check your connection."));
    };
    document.head.appendChild(sc);
  });
  async function dln(path, params) {
    const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== undefined && v !== null && v !== ""));
    let r;
    try {
      r = await fetch(SOLCFG.api + path + (params ? "?" + q : "")).then(x => x.json());
    } catch (e) {
      throw new Error("Could not reach the bridge service. Try again in a minute.");
    }
    if (r && (r.errorCode || r.errorMessage || r.errorId)) {
      const m = String(r.errorMessage || r.errorId || r.errorCode);
      throw new Error(/HOOK|simulat/i.test(m) ? "The purchase on BNB Chain would not go through right now (" + m + ")." : "Bridge: " + m);
    }
    return r;
  }
  async function solPrice() {
    const r = await dln("/dln/order/create-tx", {
      srcChainId: SOLCFG.chainId,
      srcChainTokenIn: SOLCFG.sol,
      srcChainTokenInAmount: "100000000",
      dstChainId: CFG.chainId,
      dstChainTokenOut: SOLCFG.usdtBsc,
      dstChainTokenOutAmount: "auto",
      prependOperatingExpenses: "false"
    });
    const usd = Number(r.estimation && r.estimation.srcChainTokenIn && r.estimation.srcChainTokenIn.approximateUsdValue) * 10;
    if (!(usd > 0)) throw new Error("Could not get the SOL price.");
    return {
      solUsd: usd,
      fixFee: BigInt(r.fixFee || "15000000")
    };
  }
  const randomRef = () => "0x" + [ ...crypto.getRandomValues(new Uint8Array(32)) ].map(b => b.toString(16).padStart(2, "0")).join("");
  function bridgeHookCalldata(opts, receiver, orderRef, deadline) {
    const path = [ SOLCFG.usdtBsc, CFG.wbnb, CFG.psyko ];
    return "0xd5cba93b" + uint(7 * 32) + uint(opts.productId) + uint(opts.quantity || 1) + addr(receiver) + uint(opts.minPsyko || 0) + b32(orderRef) + uint(deadline) + arr(path);
  }
  async function amountsOut(amount, path) {
    const r = await call(CFG.router, "0xd06ca61f" + uint(amount) + uint(64) + arr(path));
    const n = Number(BigInt("0x" + r.slice(64, 128)));
    return BigInt("0x" + r.slice(64 * (1 + n), 64 * (2 + n)));
  }
  async function quoteSolana(opts, token, receiver, solAccount, price) {
    if (!CFG.zap) throw new Error("This payment option is not active yet.");
    const p = price || await solPrice();
    const feeUsd = Number(p.fixFee) / 1e9 * p.solUsd;
    const spendUsd = opts.usd - feeUsd;
    if (spendUsd <= 0) throw new Error("Bridge fee too high right now.");
    const amount = token === "USDC" ? BigInt(Math.floor(spendUsd * 1e6)) : BigInt(Math.floor(spendUsd / p.solUsd * 1e9));
    const orderRef = opts.orderRef || randomRef();
    const deadline = Math.floor(Date.now() / 1e3) + 3 * 3600;
    const params = {
      srcChainId: SOLCFG.chainId,
      srcChainTokenIn: token === "USDC" ? SOLCFG.usdc : SOLCFG.sol,
      srcChainTokenInAmount: amount.toString(),
      dstChainId: CFG.chainId,
      dstChainTokenOut: SOLCFG.usdtBsc,
      dstChainTokenOutAmount: "auto",
      prependOperatingExpenses: "false"
    };
    if (solAccount) Object.assign(params, {
      dstChainTokenOutRecipient: receiver,
      dstChainOrderAuthorityAddress: receiver,
      srcChainOrderAuthorityAddress: solAccount,
      senderAddress: solAccount,
      dlnHook: JSON.stringify({
        type: "evm_transaction_call",
        data: {
          to: CFG.zap,
          calldata: bridgeHookCalldata(opts, receiver, orderRef, deadline),
          gas: SOLCFG.hookGas
        }
      })
    });
    const r = await dln("/dln/order/create-tx", params);
    const out = r.estimation && r.estimation.dstChainTokenOut;
    const usdtOut = BigInt(out && (out.recommendedAmount || out.amount) || 0);
    const storePrice = (await quote(opts.productId, opts.quantity || 1)).total;
    const psykoOut = usdtOut ? await amountsOut(usdtOut * 995n / 1000n, [ SOLCFG.usdtBsc, CFG.wbnb, CFG.psyko ]) : 0n;
    if (psykoOut < storePrice * 101n / 100n) throw new Error("After the bridge fee, $" + opts.usd + " is not quite enough right now (≈ $" + (Number(usdtOut / 10n ** 14n) / 1e4).toFixed(2) + " would arrive). Try again later or pay on BNB Chain.");
    return {
      token: token,
      amount: amount,
      feeUsd: feeUsd,
      usdtOut: usdtOut,
      psykoOut: psykoOut,
      storePrice: storePrice,
      bonus: psykoOut - storePrice,
      orderId: r.orderId,
      tx: r.tx,
      orderRef: orderRef
    };
  }
  const hexBytes = h => {
    const x = String(h).replace(/^0x/, "");
    const u = new Uint8Array(x.length / 2);
    for (let i = 0; i < u.length; i++) u[i] = parseInt(x.substr(i * 2, 2), 16);
    return u;
  };
  async function signAndSendSolana(provider, txHex) {
    const web3 = await loadWeb3();
    const tx = web3.VersionedTransaction.deserialize(hexBytes(txHex));
    const res = await provider.signAndSendTransaction(tx);
    return String(res && res.signature || res);
  }
  async function orderStatus(orderId) {
    try {
      const r = await fetch(SOLCFG.api + "/dln/order/" + orderId + "/status").then(x => x.json());
      return r && r.status;
    } catch (e) {
      return null;
    }
  }
  async function payFromSolana(opts) {
    if (!CFG.zap) throw new Error("This payment option is not active yet.");
    const w = await connect();
    const receiver = opts.receiver || w.account;
    if (opts.licenceId && await hasLicence(opts.licenceId, receiver)) throw new Error("This wallet already owns this licence.");
    css();
    const veil = document.createElement("div");
    veil.className = "pc-veil";
    const short = receiver.slice(0, 6) + "…" + receiver.slice(-4);
    veil.innerHTML = `<div class="pc-box" role="dialog" aria-label="Pay from Solana"><button class="pc-x" aria-label="Close">×</button>\n      <h3>${escHtml(opts.label || "Checkout")} · Solana</h3>\n      <p class="pc-note" style="margin-top:0">Licence and bonus PSYKO go to your BNB Chain address <b>${short}</b> (the wallet connected here).</p>\n      <div data-step="wallets"></div><div data-step="tokens"></div><div class="pc-status" hidden></div>\n      <p class="pc-note">Total about <b>$${opts.usd}</b>, bridge fee included. The bridge fee makes the PSYKO bonus smaller than when paying on BNB Chain. Delivery usually takes under a minute.</p></div>`;
    document.body.appendChild(veil);
    const $ = q => veil.querySelector(q);
    const status = (t, err) => {
      const e = $(".pc-status");
      e.hidden = !t;
      e.textContent = t || "";
      e.classList.toggle("err", !!err);
    };
    let busy = false, finished = false, rejectOuter;
    const close = () => {
      if (busy) return;
      veil.remove();
      if (!finished) rejectOuter(Object.assign(new Error("Cancelled."), {
        code: 4001
      }));
    };
    $(".pc-x").onclick = close;
    veil.onclick = e => {
      if (e.target === veil) close();
    };
    return new Promise((resolve, reject) => {
      rejectOuter = reject;
      const ws = solWallets();
      $('[data-step="wallets"]').innerHTML = ws.length ? ws.map((x, i) => `<button class="pc-w" data-i="${i}"><span>${escHtml(x.name)}<small>connect your Solana wallet</small></span></button>`).join("") : `<p class="pc-note">No Solana wallet found in this browser. Install <a href="https://phantom.com" target="_blank" rel="noopener">Phantom</a> or <a href="https://solflare.com" target="_blank" rel="noopener">Solflare</a>, then reload this page.</p>`;
      veil.querySelectorAll('[data-step="wallets"] .pc-w').forEach(b => b.onclick = async () => {
        const sw = ws[Number(b.dataset.i)];
        let solAccount;
        try {
          status("Connecting " + sw.name + "…");
          const c = await sw.provider.connect();
          solAccount = String(c && c.publicKey || sw.provider.publicKey);
        } catch (e) {
          status("The Solana wallet did not connect.", true);
          return;
        }
        $('[data-step="wallets"]').innerHTML = `<p class="pc-note" style="margin:0 0 6px">Solana: <b>${escHtml(solAccount.slice(0, 4) + "…" + solAccount.slice(-4))}</b> (${escHtml(sw.name)})</p>`;
        $('[data-step="tokens"]').innerHTML = [ "SOL", "USDC" ].map(t => `<button class="pc-w" data-t="${t}" disabled><span>Pay with ${t}<small data-q="${t}">working out the price…</small></span></button>`).join("");
        status("");
        let price;
        try {
          price = await solPrice();
        } catch (e) {
          status(e.message, true);
          return;
        }
        const quotes = {};
        await Promise.all([ "SOL", "USDC" ].map(async t => {
          const el = $(`[data-q="${t}"]`);
          try {
            const q = await quoteSolana(opts, t, receiver, null, price);
            quotes[t] = q;
            el.textContent = "≈ " + (t === "SOL" ? (Number(q.amount) / 1e9).toFixed(4) : (Number(q.amount) / 1e6).toFixed(2)) + " " + t + (t === "USDC" ? " + " + (Number(price.fixFee) / 1e9).toFixed(3) + " SOL fee" : " (fee included)") + " · bonus ≈ " + fmt(q.bonus, 0) + " PSYKO";
            $(`[data-t="${t}"]`).disabled = false;
          } catch (e) {
            el.textContent = e.message;
          }
        }));
        veil.querySelectorAll('[data-step="tokens"] .pc-w').forEach(tb => tb.onclick = async () => {
          if (busy || tb.disabled) return;
          busy = true;
          veil.querySelectorAll('[data-step="tokens"] .pc-w').forEach(x => x.disabled = true);
          try {
            status("Preparing the order…");
            const pre = quotes[tb.dataset.t];
            const q = await quoteSolana({
              ...opts,
              minPsyko: pre.storePrice + pre.bonus / 2n
            }, tb.dataset.t, receiver, solAccount, price);
            status("Confirm in " + sw.name + "…");
            const sig = await signAndSendSolana(sw.provider, q.tx.data);
            status("Sent on Solana. Waiting for delivery on BNB Chain…\nOrder: " + q.orderId);
            const t0 = Date.now();
            for (;;) {
              await new Promise(s => setTimeout(s, 4e3));
              if (await hasLicence(opts.licenceId, receiver)) {
                finished = true;
                busy = false;
                veil.remove();
                return resolve({
                  hash: sig,
                  orderId: q.orderId,
                  quoted: q.storePrice,
                  bonus: q.bonus,
                  paidWith: tb.dataset.t + " (Solana)"
                });
              }
              const st = await orderStatus(q.orderId);
              if (st && /Fulfilled|SentUnlock|ClaimedUnlock/.test(st) && Date.now() - t0 > 2e4 && !await hasLicence(opts.licenceId, receiver)) {
                busy = false;
                status("The bridge delivered, but the purchase could not finish, so the USDT was sent to " + short + " on BNB Chain instead. Nothing is lost - you can buy with that USDT here.", true);
                return;
              }
              if (st && /Cancel/.test(st)) {
                busy = false;
                status("The order was cancelled; the money goes back to your Solana wallet.", true);
                return;
              }
              if (Date.now() - t0 > 15 * 60 * 1e3) {
                busy = false;
                status("Still waiting for the bridge. Track it at app.debridge.finance (order " + q.orderId + "). The licence will appear in your wallet when it arrives.", true);
                return;
              }
            }
          } catch (e) {
            busy = false;
            status(e && e.code === 4001 ? "You cancelled in the wallet." : e && e.message || String(e), true);
            veil.querySelectorAll('[data-step="tokens"] .pc-w').forEach(x => x.disabled = !quotes[x.dataset.t]);
          }
        });
      });
    });
  }
  async function redeemCode(code) {
    const res = await fetch(CFG.gateBase + "code712.php", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        code: String(code || "")
      })
    }).then(r => r.json()).catch(() => ({
      ok: false,
      error: "Could not reach the server."
    }));
    if (!res.ok) throw new Error(res.error || "Invalid coupon code.");
    return res;
  }
  const downloadHref = (relUrl, lang) => new URL(CFG.gateBase + relUrl + (lang ? "&lang=" + encodeURIComponent(lang) : ""), location.href).href;
  function startDownload(href) {
    const a = document.createElement("a");
    a.href = href;
    a.rel = "noopener";
    a.target = "_blank";
    document.body.appendChild(a);
    a.click();
    a.remove();
  }
  const account = () => current ? current.account : null;
  window.PsykoConnect = {
    CFG: CFG,
    connect: connect,
    ensureBsc: ensureBsc,
    buy: buy,
    quote: quote,
    hasLicence: hasLicence,
    downloadSignIn: downloadSignIn,
    redeemCode: redeemCode,
    downloadHref: downloadHref,
    startDownload: startDownload,
    account: account,
    choosePayment: choosePayment,
    payWithAny: payWithAny,
    quoteAny: quoteAny,
    payFromSolana: payFromSolana,
    quoteSolana: quoteSolana,
    couponFromUrl: couponFromUrl,
    wallets: () => [ ...found.values() ].map(w => w.info)
  };
})();