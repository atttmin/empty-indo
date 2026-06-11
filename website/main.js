/**
 * Download links — update these when App Store / TestFlight / release builds ship.
 * Mac defaults to latest GitHub Release (or repo home if none).
 */
const DOWNLOADS = {
  mac: "https://github.com/DaviRain-Su/empty/releases/latest",
  appStore: "", // e.g. https://apps.apple.com/app/idXXXXXXXX
  testFlight: "", // e.g. https://testflight.apple.com/join/XXXXXXXX
};

function applyDownloads() {
  const mac = document.getElementById("dl-mac");
  const appStore = document.getElementById("dl-appstore");
  const testFlight = document.getElementById("dl-testflight");
  const heroMac = document.getElementById("hero-mac");
  const heroIos = document.getElementById("hero-ios");
  const badgeAppStore = document.getElementById("badge-appstore");
  const badgeTestFlight = document.getElementById("badge-testflight");

  if (DOWNLOADS.mac) {
    mac.href = DOWNLOADS.mac;
    heroMac.href = DOWNLOADS.mac;
  }

  if (DOWNLOADS.appStore) {
    appStore.href = DOWNLOADS.appStore;
    badgeAppStore.textContent = "已上架";
    badgeAppStore.classList.remove("badge-soon");
  } else {
    appStore.addEventListener("click", (e) => {
      e.preventDefault();
      alert("App Store 正式版即将上架，请先通过 TestFlight 加入内测。");
    });
  }

  if (DOWNLOADS.testFlight) {
    testFlight.href = DOWNLOADS.testFlight;
    heroIos.href = DOWNLOADS.testFlight;
    badgeTestFlight.textContent = "开放内测";
  } else {
    testFlight.addEventListener("click", (e) => {
      e.preventDefault();
      alert(
        "TestFlight 内测链接即将开放。\n\n关注 GitHub 仓库获取邀请码，或自行用 Xcode 构建 iOS 版。"
      );
    });
    heroIos.href = "#download";
  }
}

applyDownloads();