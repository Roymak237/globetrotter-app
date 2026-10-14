import { AnimatePresence, motion } from "framer-motion";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useEffect, useRef, useState, type CSSProperties } from "react";

import GradientButton from "../components/GradientButton";
import { EXPLORATIONS } from "../data/media";

gsap.registerPlugin(ScrollTrigger);

/** Alternating tilts, so the grid never reads as a spreadsheet of squares. */
const TILT = [-3, 2, -1.5, 3, -2, 1.5];

export default function Explorations() {
  const section = useRef<HTMLElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const columnA = useRef<HTMLDivElement>(null);
  const columnB = useRef<HTMLDivElement>(null);
  const [lightbox, setLightbox] = useState<number | null>(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      // Pinning and scroll-scrubbed parallax are both wrong on a phone: the
      // section would be three screens of almost nothing, and pinned elements
      // fight mobile Safari's collapsing address bar. matchMedia gives the
      // small breakpoint a plain stacked grid and reverts cleanly on resize.
      const mm = gsap.matchMedia();

      mm.add("(min-width: 768px) and (prefers-reduced-motion: no-preference)", () => {
        if (!section.current || !content.current) return;

        ScrollTrigger.create({
          trigger: section.current,
          start: "top top",
          end: "bottom bottom",
          pin: content.current,
          // The heading is a backdrop for the drifting photographs rather than
          // a step in the scroll, so it must not add height of its own.
          pinSpacing: false,
        });

        // Two columns travelling at different rates is the whole effect; equal
        // rates would just look like a slower page.
        const drift = (el: HTMLElement | null, distance: number) => {
          if (!el) return;
          gsap.fromTo(
            el,
            { y: distance },
            {
              y: -distance,
              ease: "none",
              scrollTrigger: {
                trigger: section.current,
                start: "top bottom",
                end: "bottom top",
                scrub: 1,
              },
            },
          );
        };

        drift(columnA.current, 120);
        drift(columnB.current, -220);
      });
    }, section);

    return () => ctx.revert();
  }, []);

  useEffect(() => {
    if (lightbox === null) return;

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setLightbox(null);
      if (e.key === "ArrowRight")
        setLightbox((i) => ((i ?? 0) + 1) % EXPLORATIONS.length);
      if (e.key === "ArrowLeft")
        setLightbox(
          (i) => ((i ?? 0) - 1 + EXPLORATIONS.length) % EXPLORATIONS.length,
        );
    };

    document.addEventListener("keydown", onKey);
    // The page behind an open lightbox must not scroll, or dismissing it
    // returns the reader somewhere they never navigated to.
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [lightbox]);

  const columns = [
    EXPLORATIONS.slice(0, 3).map((item, i) => ({ item, index: i })),
    EXPLORATIONS.slice(3).map((item, i) => ({ item, index: i + 3 })),
  ];

  return (
    <>
      <section
        id="gallery"
        ref={section}
        className="relative bg-bg md:min-h-[300vh]"
      >
        {/* Layer 1 — the pinned centre. */}
        <div
          ref={content}
          className="relative z-10 flex flex-col items-center justify-center px-6 py-16 text-center md:h-screen md:py-0"
        >
          <div className="mb-5 flex items-center gap-3">
            <span className="h-px w-8 bg-stroke" />
            <span className="text-xs uppercase tracking-[0.3em] text-muted">
              Explorations
            </span>
            <span className="h-px w-8 bg-stroke" />
          </div>

          <h2 className="text-4xl leading-[1.05] tracking-tight text-text-primary md:text-6xl lg:text-7xl">
            Visual <span className="font-display italic">playground</span>
          </h2>

          <p className="mt-4 max-w-md text-balance text-sm text-muted md:text-base">
            Photographs from the catalogue — every one of them a place you can
            actually add to a day.
          </p>

          {/* The gallery this opens is the one directly behind this heading, so
              it opens in place. It used to link to /app/, which is the app's
              home screen rather than a gallery and 404s wherever the Flutter
              build is not mounted alongside the page. */}
          <GradientButton onClick={() => setLightbox(0)} className="mt-8">
            Open the gallery
            <span aria-hidden="true">↗</span>
          </GradientButton>
        </div>

        {/* Layer 2 — the drifting columns, over the heading on desktop and a
            plain grid underneath it on mobile. */}
        <div className="px-6 pb-16 md:pointer-events-none md:absolute md:inset-0 md:z-20 md:px-0 md:pb-0">
          <div className="mx-auto grid max-w-[1400px] grid-cols-2 gap-6 md:gap-12 lg:gap-40">
            {columns.map((column, c) => (
              <div
                key={c}
                ref={c === 0 ? columnA : columnB}
                className="flex flex-col items-center gap-6 md:gap-16 lg:gap-24"
              >
                {column.map(({ item, index }) => (
                  <button
                    key={item.src}
                    type="button"
                    onClick={() => setLightbox(index)}
                    // The tilt is driven through a custom property and applied
                    // inside `transform`, not via the standalone `rotate`
                    // property: `rotate` cannot be transitioned together with
                    // Tailwind's scale utilities, and an inline style would
                    // outrank the hover rule that straightens the card.
                    style={{ "--tilt": `${TILT[index]}deg` } as CSSProperties}
                    className="group relative aspect-square w-full max-w-[320px] overflow-hidden rounded-2xl border border-stroke bg-surface transition-transform duration-500 [transform:rotate(var(--tilt))] hover:[transform:rotate(0deg)_scale(1.03)] md:pointer-events-auto"
                  >
                    <img
                      src={item.src}
                      alt={item.alt}
                      loading="lazy"
                      decoding="async"
                      className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-110"
                    />
                    <span
                      className="halftone pointer-events-none absolute inset-0 opacity-20 mix-blend-multiply"
                      aria-hidden="true"
                    />
                    <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent p-4 text-left text-xs text-white/85">
                      {item.alt}
                    </span>
                  </button>
                ))}
              </div>
            ))}
          </div>
        </div>
      </section>

      <AnimatePresence>
        {lightbox !== null && (
          <motion.div
            role="dialog"
            aria-modal="true"
            aria-label={EXPLORATIONS[lightbox].alt}
            className="fixed inset-0 z-[9998] flex items-center justify-center bg-black/90 p-6 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.25 }}
            onClick={() => setLightbox(null)}
          >
            <motion.figure
              className="max-h-full"
              initial={{ scale: 0.94, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.94, opacity: 0 }}
              transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
            >
              <img
                src={EXPLORATIONS[lightbox].src}
                alt={EXPLORATIONS[lightbox].alt}
                className="max-h-[80vh] rounded-2xl object-contain"
              />
              <figcaption className="mt-4 text-center text-sm text-muted">
                {EXPLORATIONS[lightbox].alt} — press Esc to close
              </figcaption>
            </motion.figure>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
