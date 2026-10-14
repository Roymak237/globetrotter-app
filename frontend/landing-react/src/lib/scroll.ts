import { useEffect, useState } from "react";

/**
 * Scrolls a section into view, accounting for the fixed navbar, and keeps the
 * URL hash in step so the position survives a copy-paste of the address bar.
 *
 * Uses scrollTo rather than scrollIntoView because the offset has to be applied
 * before the scroll, not corrected after it — correcting after produces a
 * visible double-jump on the slower phones this app is mostly opened on.
 */
export function scrollToSection(id: string) {
  const target = document.getElementById(id);
  if (!target) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const OFFSET = 88;

  window.scrollTo({
    top: target.getBoundingClientRect().top + window.scrollY - OFFSET,
    behavior: reduced ? "auto" : "smooth",
  });

  // replaceState, not a hash assignment: assigning the hash would trigger the
  // browser's own instant jump and undo the smooth scroll above.
  window.history.replaceState(null, "", id === "home" ? "/" : `#${id}`);
}

/**
 * Which section is currently under the navbar. Driven by IntersectionObserver
 * rather than a scroll handler so it costs nothing while the page is still.
 */
export function useActiveSection(ids: string[]): string {
  const [active, setActive] = useState(ids[0] ?? "");

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        // More than one section can straddle the band at once, so the most
        // visible one wins instead of whichever fired last.
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (visible) setActive(visible.target.id);
      },
      // A band across the upper-middle of the viewport: a section counts as
      // current once its top third is on screen, not once it is centred.
      { rootMargin: "-20% 0px -60% 0px", threshold: [0, 0.25, 0.5, 1] },
    );

    const nodes = ids
      .map((id) => document.getElementById(id))
      .filter((n): n is HTMLElement => n !== null);
    nodes.forEach((n) => observer.observe(n));

    return () => observer.disconnect();
  }, [ids]);

  return active;
}
