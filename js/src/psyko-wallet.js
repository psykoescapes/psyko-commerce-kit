(function() {
  var DEFAULT_APK = "https://www.psykovsky.com/apk/PSYKO-Wallet.apk";
  var ua = navigator.userAgent || "";
  var inApp = /PsykoWallet\//.test(ua);
  var android = /Android/i.test(ua);
  var ios = /iPhone|iPad|iPod/i.test(ua) || navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  function setup(a) {
    if (a.__psykoWallet) return;
    a.__psykoWallet = true;
    var apk = a.getAttribute("data-apk") || DEFAULT_APK;
    var open = a.getAttribute("data-open") || location.href.split("#")[0];
    if (inApp || ios) {
      (a.closest && a.closest("[data-psyko-wallet-box]") || a).style.display = "none";
      return;
    }
    a.removeAttribute("target");
    if (android) {
      a.href = "intent://open?url=" + encodeURIComponent(open) + "#Intent;scheme=psykowallet;package=com.psykovsky.wallet;S.browser_fallback_url=" + encodeURIComponent(apk) + ";end";
      a.textContent = "◆ Open in PSYKO Wallet";
      a.title = "Opens this page in the PSYKO Wallet app - or downloads the app if you don't have it yet";
    } else {
      a.href = apk;
      a.setAttribute("download", "");
      a.textContent = "◆ PSYKO Wallet for Android";
      a.title = "Download the PSYKO Wallet app (.apk) for Android phones";
    }
  }
  function run() {
    var list = document.querySelectorAll("[data-psyko-wallet]");
    for (var i = 0; i < list.length; i++) setup(list[i]);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run); else run();
})();