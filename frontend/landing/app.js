/* Kamer-Go landing page behaviour.
   Three jobs: shrink the nav on scroll, reveal sections as they enter the
   viewport, and build the destination grid from the live API so the marketing
   page can never advertise a catalogue the app does not actually serve. */

(() => {
  "use strict";

  /* The Flutter build is published under /app/, and Flutter nests declared
     asset folders one level deeper, hence the doubled "assets" segment. */
  const MEDIA_ROOT = "/media/";
  const MAX_TILES = 12;

  /* ---------------------------------------------------------------- nav */
  const nav = document.getElementById("nav");
  if (nav) {
    const syncNav = () => nav.classList.toggle("is-stuck", window.scrollY > 12);
    syncNav();
    window.addEventListener("scroll", syncNav, { passive: true });
  }

  /* --------------------------------------------------------------- year */
  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  /* ------------------------------------------------------------ reveals */
  const revealTargets = document.querySelectorAll(
    ".section, .hero__actions, .stats, .card, .cta-band"
  );

  // Without IntersectionObserver the content must still be readable, so the
  // reveal class is only ever added when we know we can also remove it.
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );

    revealTargets.forEach((el) => {
      el.classList.add("reveal");
      observer.observe(el);
    });
  }

  /* --------------------------------------------------------- stat count */
  const countUp = (el, target) => {
    const duration = 1100;
    const start = performance.now();

    const step = (now) => {
      const progress = Math.min((now - start) / duration, 1);
      // Ease-out cubic: fast first, settling gently on the final number.
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = String(Math.round(target * eased));
      if (progress < 1) requestAnimationFrame(step);
    };

    requestAnimationFrame(step);
  };

  const animateCounter = (el) => {
    const target = Number(el.dataset.countTo);
    if (!Number.isFinite(target) || target <= 0) return;

    if (!("IntersectionObserver" in window)) {
      el.textContent = String(target);
      return;
    }

    const observer = new IntersectionObserver(
      (entries, self) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          countUp(el, target);
          self.unobserve(entry.target);
        });
      },
      { threshold: 0.5 }
    );

    observer.observe(el);
  };

  document.querySelectorAll("[data-count-to]").forEach(animateCounter);

  /* -------------------------------------------------------- destinations */
  const grid = document.getElementById("destinationGrid");
  const destinationStat = document.getElementById("statDestinations");

  /** Prefer the bundled asset; fall back to the remote credit image. */
  const imageFor = (destination) => {
    const asset = (destination.image_asset || "").trim();
    if (asset) {
      // Asset filenames contain spaces, so each path segment is encoded
      // individually to keep the separators intact.
      return MEDIA_ROOT + asset.split("/").map(encodeURIComponent).join("/");
    }
    return destination.image_url || "";
  };

  const buildTile = (destination) => {
    const tile = document.createElement("article");
    tile.className = "tile";

    const img = document.createElement("img");
    img.src = imageFor(destination);
    img.alt = destination.name || "";
    img.loading = "lazy";
    img.decoding = "async";

    // A bundled asset that 404s still has a usable remote fallback.
    img.addEventListener(
      "error",
      () => {
        if (destination.image_url && img.src !== destination.image_url) {
          img.src = destination.image_url;
        } else {
          tile.remove();
        }
      },
      { once: true }
    );

    const meta = document.createElement("div");
    meta.className = "tile__meta";

    const name = document.createElement("span");
    name.className = "tile__name";
    name.textContent = destination.name || "";

    const region = document.createElement("span");
    region.className = "tile__region";
    region.textContent = destination.region || "Cameroon";

    meta.append(name, region);
    tile.append(img, meta);
    return tile;
  };

  const renderDestinations = async () => {
    if (!grid) return;

    try {
      const response = await fetch("/api/destinations", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) throw new Error("HTTP " + response.status);

      const payload = await response.json();
      const all = Array.isArray(payload) ? payload : payload.destinations || [];

      if (destinationStat && all.length) {
        destinationStat.dataset.countTo = String(all.length);
        destinationStat.textContent = String(all.length);
      }

      const withImages = all.filter((d) => imageFor(d));
      if (!withImages.length) throw new Error("no illustrated destinations");

      const fragment = document.createDocumentFragment();
      withImages.slice(0, MAX_TILES).forEach((d) => fragment.append(buildTile(d)));

      grid.replaceChildren(fragment);
      grid.setAttribute("aria-busy", "false");
    } catch (error) {
      console.error("Could not load destinations:", error);
      grid.innerHTML =
        '<p class="tiles__error">Destinations are taking a moment. ' +
        '<a href="/app/">Open the app</a> to browse them all.</p>';
      grid.setAttribute("aria-busy", "false");
    }
  };

  renderDestinations();
})();
