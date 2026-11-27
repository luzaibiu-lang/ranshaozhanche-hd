(function (root) {
  "use strict";

  function isMobileDevice(info) {
    const ua = String(info.userAgent || "");
    const platform = String(info.platform || "");
    const hints = info.userAgentData || {};
    const hintPlatform = String(hints.platform || "");
    const touches = Number(info.maxTouchPoints || 0);

    // A Windows touchscreen is still a desktop, irrespective of its pointer.
    if (/Windows(?: NT| Phone)?/i.test(ua)) return false;
    if (/Android|iPhone|iPad|iPod|HarmonyOS|OpenHarmony|HongMeng/i.test(ua)) return true;
    if (/^(Android|iOS|iPadOS|HarmonyOS)$/i.test(hintPlatform)) return true;
    // iPadOS can request desktop sites and identify itself as a Macintosh.
    if (touches > 1 && (/Macintosh/i.test(ua) || platform === "MacIntel")) return true;
    if (/^(Windows|macOS|Linux|Chrome OS)$/i.test(hintPlatform)
      || /^(Win|Mac|Linux|CrOS|X11)/i.test(platform)
      || /Windows NT|Macintosh|X11|CrOS|Linux x86_64/i.test(ua)) return false;
    return hints.mobile === true || /\bMobile\b/i.test(ua);
  }

  const mobile = isMobileDevice(root.navigator || {});
  // Both the HTML shell and Godot read this same, stable session profile.
  // Window size, orientation and connecting a mouse never change the device.
  root.BurningChariotDevice = Object.freeze({
    mobile,
    mode: mobile ? "mobile" : "desktop",
    isMobileDevice
  });
})(globalThis);
