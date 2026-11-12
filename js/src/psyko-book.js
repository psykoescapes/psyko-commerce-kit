window.PsykoBook = (() => {
  let lastBtn = null;
  const say = (msg, bad) => {
    console.log("[psyko-book]", msg);
    try {
      let box = document.getElementById("pb-toast");
      if (!box) {
        box = document.createElement("div");
        box.id = "pb-toast";
        box.style.cssText = "position:fixed;left:50%;top:22px;transform:translateX(-50%);z-index:99999;" + "max-width:min(560px,92vw);padding:14px 20px;border-radius:12px;font:600 15px/1.45 'Exo 2',sans-serif;" + "color:#fff;box-shadow:0 6px 28px rgba(0,0,0,.45);text-align:center;transition:opacity .3s;";
        document.body.appendChild(box);
      }
      box.textContent = msg;
      box.style.background = bad ? "#7a2340" : "#1d6b4f";
      box.style.opacity = "1";
      box.style.display = "block";
      clearTimeout(box._t);
      box._t = setTimeout(() => {
        box.style.opacity = "0";
      }, bad ? 7e3 : 5e3);
      const card = lastBtn && lastBtn.closest(".referral, .stream-card");
      const st = card && card.querySelector(".pb-status");
      if (st) {
        st.textContent = msg;
        st.style.color = bad ? "#ff9db8" : "#7ff0d6";
      }
    } catch (e) {
      alert(msg);
    }
  };
  const val = sel => {
    const el = document.querySelector(".stream-section " + sel);
    return el ? el.value.trim() : "";
  };
  async function sha256hex(text) {
    const d = await crypto.subtle.digest("SHA-256", (new TextEncoder).encode(text));
    return "0x" + Array.from(new Uint8Array(d)).map(b => b.toString(16).padStart(2, "0")).join("");
  }
  let busy = false;
  async function stream(btn) {
    lastBtn = btn;
    if (busy) return;
    const email = val('input[type="email"]'), date = val('input[type="date"]'), time = val('input[type="time"]');
    const hours = Math.max(1, Math.min(6, parseInt(val("input.stream-range") || "1", 10) || 1));
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return say("Please enter your email, so Psykovsky can contact you about the stream.", true);
    if (!date) return say("Please pick an approximate date.", true);
    const label = btn && btn.querySelector(".address"), old = label ? label.textContent : "";
    busy = true;
    try {
      if (label) label.textContent = "CONFIRM IN WALLET…";
      const booking = {
        email: email,
        date: date,
        time: time,
        hours: hours,
        ts: Date.now()
      };
      const orderRef = await sha256hex(JSON.stringify(booking));
      const w = await PsykoConnect.connect();
      const r = await PsykoConnect.buy({
        productId: 2,
        quantity: hours,
        orderRef: orderRef
      });
      await fetch("/gate/booking712.php", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          ...booking,
          tx: r.hash,
          orderRef: orderRef,
          wallet: w.account
        })
      }).catch(() => {});
      say("Booked! " + hours + " hour" + (hours > 1 ? "s" : "") + " on " + date + ". Psykovsky will contact you at " + email + ".");
    } catch (e) {
      say(e && e.message || "The booking did not go through.", true);
    } finally {
      busy = false;
      if (label) label.textContent = old;
    }
  }
  const KMXI = {
    productId: 11,
    usd: 160,
    store: "0x64f2CddD7Fd2D8E2FFe8Dfe99B30A95678D63c10",
    psyko: "0xaaD978c2155FAccF64b93A8D2B8A5D8f2317D308",
    wbnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
    usdt: "0x55d398326f99059fF775485246999027B3197955",
    factory: "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
  };
  let kmSoldOut = false, kmReady = null;
  const rpc = () => new Web3("https://bsc-dataseed.binance.org/");
  const FACTORY_ABI = [ {
    name: "getPair",
    type: "function",
    stateMutability: "view",
    inputs: [ {
      type: "address"
    }, {
      type: "address"
    } ],
    outputs: [ {
      type: "address"
    } ]
  } ];
  const PAIR_ABI = [ {
    name: "getReserves",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [ {
      type: "uint112"
    }, {
      type: "uint112"
    }, {
      type: "uint32"
    } ]
  } ];
  const STORE_ABI = [ {
    name: "product",
    type: "function",
    stateMutability: "view",
    inputs: [ {
      type: "uint256"
    } ],
    outputs: [ {
      type: "uint256"
    }, {
      type: "uint256"
    }, {
      type: "uint256"
    }, {
      type: "bool"
    }, {
      type: "bool"
    }, {
      type: "address[]"
    }, {
      type: "uint16[]"
    } ]
  } ];
  async function reserves(web3, a, b) {
    const pair = await new web3.eth.Contract(FACTORY_ABI, KMXI.factory).methods.getPair(a, b).call();
    const r = await new web3.eth.Contract(PAIR_ABI, pair).methods.getReserves().call();
    return a.toLowerCase() < b.toLowerCase() ? [ Number(r[0]), Number(r[1]) ] : [ Number(r[1]), Number(r[0]) ];
  }
  async function kmxiRefresh() {
    if (!window.Web3) return;
    const web3 = rpc();
    try {
      const [bnbA, psy] = await reserves(web3, KMXI.wbnb, KMXI.psyko);
      const [bnbB, usd] = await reserves(web3, KMXI.wbnb, KMXI.usdt);
      const psyko = Math.ceil(KMXI.usd / (usd / bnbB) * (psy / bnbA));
      document.querySelectorAll(".kmxi-psyko").forEach(el => {
        el.textContent = "≈ " + psyko.toLocaleString("en-US") + " PSYKO (" + KMXI.usd + " USD)";
      });
    } catch (e) {
      console.warn("KM XI price:", e);
    }
    try {
      const p = await new web3.eth.Contract(STORE_ABI, KMXI.store).methods.product(KMXI.productId).call();
      kmReady = String(p[0]) !== "0" || String(p[1]) !== "0";
      kmSoldOut = kmReady && !p[3];
    } catch (e) {
      console.warn("KM XI status:", e);
    }
    document.querySelectorAll(".kmxi-buy").forEach(b => {
      const l = b.querySelector(".address");
      if (l && !busy) l.textContent = kmSoldOut ? "SOLD OUT" : "BUY TICKET";
      b.style.opacity = kmSoldOut ? ".55" : "";
    });
  }
  const startKm = () => {
    setTimeout(kmxiRefresh, 2500);
    setInterval(kmxiRefresh, 6e4);
  };
  if (document.readyState === "complete") startKm(); else window.addEventListener("load", startKm);
  async function kmxi(btn) {
    lastBtn = btn;
    console.log("[KM XI] buy clicked", {
      busy: busy,
      kmReady: kmReady,
      kmSoldOut: kmSoldOut,
      connect: !!window.PsykoConnect
    });
    if (busy) return;
    if (kmSoldOut) return say("All 5 tickets are sold out.", true);
    if (kmReady === false) return say("Ticket sales open shortly - please check back soon.", true);
    if (!window.PsykoConnect) return say("The wallet module did not load. Please reload the page.", true);
    const el = document.querySelector(".kmxi-email"), email = el ? el.value.trim() : "";
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return say("Please enter your email, so your ticket details can reach you.", true);
    const label = btn && btn.querySelector(".address"), old = label ? label.textContent : "";
    busy = true;
    try {
      if (label) label.textContent = "CONFIRM IN WALLET…";
      say("Connecting your wallet...");
      const ticket = {
        kind: "kmxi-ticket",
        event: "Karacus Marakus XI",
        email: email,
        date: "2027-01-29",
        time: "",
        hours: 1,
        ts: Date.now()
      };
      const orderRef = await sha256hex(JSON.stringify(ticket));
      const w = await PsykoConnect.connect();
      const r = await PsykoConnect.buy({
        productId: KMXI.productId,
        quantity: 1,
        orderRef: orderRef
      });
      await fetch("/gate/booking712.php", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          ...ticket,
          tx: r.hash,
          orderRef: orderRef,
          wallet: w.account
        })
      }).catch(() => {});
      say("Your Karacus Marakus XI ticket is confirmed! Details go to " + email + ".");
    } catch (e) {
      say(e && e.message || "The purchase did not go through.", true);
    } finally {
      busy = false;
      if (label) label.textContent = old;
      kmxiRefresh();
    }
  }
  return {
    stream: stream,
    kmxi: kmxi
  };
})();

console.log("[psyko-book] loaded");