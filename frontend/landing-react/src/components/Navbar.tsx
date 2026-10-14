import { useEffect, useMemo, useState } from "react";

import { scrollToSection, useActiveSection } from "../lib/scroll";

const LINKS = [
  { id: "home", label: "Home" },
  { id: "explore", label: "Explore" },
  { id: "guides", label: "Guides" },
] as const;

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const ids = useMemo(() => LINKS.map((l) => l.id), []);
  const active = useActiveSection(ids);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 100);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4 md:pt-6">
      <nav
        aria-label="Primary"
        className={`inline-flex items-center rounded-full border border-white/10 bg-surface px-2 py-2 backdrop-blur-md transition-shadow duration-300 ${
          scrolled ? "shadow-md shadow-black/10" : ""
        }`}
      >
        {/* Logo: a gradient ring with the page background punched out of the
            middle, so the mark is the ring rather than a filled disc. */}
        <button
          type="button"
          onClick={() => scrollToSection("home")}
          aria-label="Kamer-Go, back to top"
          className="group accent-gradient relative h-9 w-9 shrink-0 rounded-full p-[1.5px] transition-transform duration-300 hover:scale-110"
        >
          <span className="accent-gradient-reverse absolute inset-0 rounded-full opacity-0 transition-opacity duration-300 group-hover:opacity-100" />
          <span className="relative flex h-full w-full items-center justify-center rounded-full bg-bg font-display text-[13px] italic text-text-primary">
            KG
          </span>
        </button>

        <span className="mx-1 hidden h-5 w-px bg-stroke sm:block" />

        {LINKS.map((link) => (
          <button
            key={link.id}
            type="button"
            onClick={() => scrollToSection(link.id)}
            aria-current={active === link.id ? "true" : undefined}
            className={`rounded-full px-3 py-1.5 text-xs transition-colors duration-200 sm:px-4 sm:py-2 sm:text-sm ${
              active === link.id
                ? "bg-stroke/50 text-text-primary"
                : "text-muted hover:bg-stroke/50 hover:text-text-primary"
            }`}
          >
            {link.label}
          </button>
        ))}

        <span className="mx-1 hidden h-5 w-px bg-stroke sm:block" />

        {/* The gradient border lives on an inset:-2px span behind the pill, so
            the ring appears on hover without the button changing size and
            nudging the rest of the bar. */}
        <a
          href="/app/"
          className="group relative rounded-full text-xs sm:text-sm"
        >
          <span
            className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
            style={{ inset: "-2px" }}
            aria-hidden="true"
          />
          <span className="relative flex items-center gap-1 rounded-full bg-surface px-3 py-1.5 text-text-primary backdrop-blur-md sm:px-4 sm:py-2">
            Open app
            <span aria-hidden="true">↗</span>
          </span>
        </a>
      </nav>
    </header>
  );
}
