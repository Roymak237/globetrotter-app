import { useEffect, useState } from "react";

import { HERO_SLIDES } from "../data/media";

const SLIDE_MS = 6000;

/**
 * The reference design runs an HLS video behind the hero. There is no footage
 * of Yaoundé in this repository and no budget for a stream, so the backdrop is
 * built from the app's own photography instead: a slow zoom on each frame with
 * a long crossfade between them reads as motion without a video element.
 *
 * Only the current and next slides are ever mounted with a decode priority; the
 * rest are plain lazy images, so the hero costs one photograph on first paint
 * rather than six.
 */
export default function KenBurnsBackdrop() {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const reduced = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    if (reduced) return;

    const id = window.setInterval(
      () => setIndex((i) => (i + 1) % HERO_SLIDES.length),
      SLIDE_MS,
    );
    return () => window.clearInterval(id);
  }, []);

  return (
    <div className="absolute inset-0 overflow-hidden" aria-hidden="true">
      {HERO_SLIDES.map((slide, i) => (
        <div
          key={slide.src}
          // The transition duration is written as an arbitrary property rather
          // than a duration utility: Tailwind cannot tell whether an arbitrary
          // duration means transition-duration or animation-duration, and warns
          // on every build until the property is named outright.
          className="absolute inset-0 transition-opacity ease-in-out [transition-duration:1600ms]"
          style={{ opacity: i === index ? 1 : 0 }}
        >
          <img
            src={slide.src}
            alt=""
            // The drift is restarted by keying the animation to the active
            // index; without the key React reuses the node and the zoom sits
            // frozen at its end state from the previous cycle.
            key={`${slide.src}-${i === index}`}
            className={`h-full w-full object-cover ${
              i === index ? "animate-ken-burns" : "scale-[1.06]"
            }`}
            loading={i === 0 ? "eager" : "lazy"}
            fetchPriority={i === 0 ? "high" : "low"}
            decoding="async"
            draggable={false}
          />
        </div>
      ))}

      {/* Two overlays, not one: the flat wash holds contrast for the headline
          anywhere on the frame, and the bottom ramp dissolves the photograph
          into the page so the section has no visible seam. */}
      <div className="absolute inset-0 bg-black/45" />
      <div className="absolute inset-0 bg-gradient-to-b from-bg/70 via-transparent to-transparent" />
      <div className="absolute inset-x-0 bottom-0 h-48 bg-gradient-to-t from-bg to-transparent" />
    </div>
  );
}

export { SLIDE_MS };
