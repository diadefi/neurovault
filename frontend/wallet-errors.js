// Expose useful wallet/RPC messages without dumping transaction payloads or secrets.
(function (root) {
  root.NV_walletError = function (error) {
    const seen = new Set(), messages = [], codes = [];
    function visit(e, depth = 0) {
      if (!e || typeof e !== "object" || seen.has(e) || depth > 8) return;
      seen.add(e);
      // Prefer the underlying RPC response to ethers' generic wrapper.
      for (const key of ["originalError", "error", "cause", "data", "info"]) visit(e[key], depth + 1);
      if (e.code !== undefined && !codes.includes(String(e.code))) codes.push(String(e.code));
      for (const key of ["reason", "shortMessage", "message"]) {
        const value = e[key];
        if (typeof value !== "string" || !value.trim()) continue;
        // ethers' full message serializes the entire request; only keep its heading.
        const message = value.split(" (error=")[0].split(" (action=")[0].slice(0, 600);
        if (/could not coalesce error|internal json-rpc error|internal error/i.test(message)) continue;
        if (!messages.includes(message)) messages.push(message);
      }
    }
    visit(error);
    let message = messages[0] || "Wallet returned an unspecified error.";
    if (codes.includes("-32002")) message = "MetaMask already has a pending request. Open MetaMask and finish or reject that request before retrying.";
    else if (codes.includes("4001") || codes.includes("ACTION_REJECTED")) message = "The wallet request was declined. No automatic retry was sent.";
    const method = error?.payload?.method || error?.info?.payload?.method;
    const details = [method, codes.length ? "code " + codes.join(" / ") : ""].filter(Boolean).join("; ");
    return message + (details ? " [" + details + "]" : "");
  };
})(globalThis);
