(function () {
  var storageKey = "acode.siteLanguage";
  var script = document.currentScript;
  var current = script && script.dataset.currentLang === "en" ? "en" : "zh";
  var zhUrl = script && script.dataset.zhUrl ? script.dataset.zhUrl : "./";
  var enUrl = script && script.dataset.enUrl ? script.dataset.enUrl : "./en/";
  var params = new URLSearchParams(window.location.search);

  function normalizeLanguage(value) {
    if (!value) return "";
    var lower = String(value).toLowerCase();
    if (lower === "en" || lower.indexOf("en-") === 0) return "en";
    if (lower === "zh" || lower === "cn" || lower.indexOf("zh-") === 0) return "zh";
    return "";
  }

  function regionFromLocale(locale) {
    if (!locale) return "";
    try {
      if (window.Intl && Intl.Locale) {
        return (new Intl.Locale(locale).region || "").toUpperCase();
      }
    } catch (error) {}
    var match = String(locale).match(/[-_]([A-Za-z]{2}|\d{3})(?:[-_]|$)/);
    return match ? match[1].toUpperCase() : "";
  }

  function browserPreferredLanguage() {
    var languages = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || navigator.userLanguage || ""];
    var primary = languages[0] || "";
    if (!/^zh(?:[-_]|$)/i.test(primary)) return "en";

    var region = regionFromLocale(primary);
    if (!region) return "zh";
    return region === "CN" || region === "HK" || region === "TW" ? "zh" : "en";
  }

  function cleanSearch() {
    var clean = new URLSearchParams(window.location.search);
    clean.delete("lang");
    var value = clean.toString();
    return value ? "?" + value : "";
  }

  function redirectTo(language) {
    var target = new URL(language === "en" ? enUrl : zhUrl, window.location.href);
    target.search = cleanSearch();
    target.hash = window.location.hash;
    window.location.replace(target.href);
  }

  var queryLanguage = normalizeLanguage(params.get("lang"));
  if (queryLanguage) {
    try {
      window.localStorage.setItem(storageKey, queryLanguage);
    } catch (error) {}
  }

  var savedLanguage = "";
  try {
    savedLanguage = normalizeLanguage(window.localStorage.getItem(storageKey));
  } catch (error) {}

  var targetLanguage = queryLanguage || savedLanguage || browserPreferredLanguage();

  if (targetLanguage && targetLanguage !== current) {
    redirectTo(targetLanguage);
    return;
  }

  if (queryLanguage && window.history && window.history.replaceState) {
    window.history.replaceState(null, "", window.location.pathname + cleanSearch() + window.location.hash);
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-lang-choice]").forEach(function (link) {
      link.addEventListener("click", function () {
        var language = normalizeLanguage(link.getAttribute("data-lang-choice"));
        if (!language) return;
        try {
          window.localStorage.setItem(storageKey, language);
        } catch (error) {}
      });
    });
  });
})();
