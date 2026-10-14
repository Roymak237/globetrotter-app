import gsap from "gsap";
import { useEffect, useRef, useState } from "react";

import KenBurnsBackdrop from "../components/KenBurnsBackdrop";
import { scrollToSection } from "../lib/scroll";

const MOODS = ["landmark", "market", "viewpoint", "long lunch"];

interface Props {
  /** Held until the loading screen is gone, so the timeline is not spent
   *  animating a hero nobody can see yet. */
  ready: boolean;
}

export default function Hero({ ready }: Props) {
  const root = useRef<HTMLElement>(null);
  const [moodIndex, setMoodIndex] = useState(0);

  useEffect(() => {
    if (!ready) return;

    const ctx = gsap.context(() => {
      const tl = gsap.timeline({ defaults: { ease: "power3.out" } });

      tl.from(".name-reveal", { opacity: 0, y: 50, duration: 1.2, delay: 0.1 });
      tl.from(
        ".blur-in",
        {
          opacity: 0,
          filter: "blur(10px)",
          y: 20,
          duration: 1,
          stagger: 0.1,
        },
        0.3,
      );
    }, root);

    // gsap.context().revert() puts every property the timeline touched back,
    // which matters under StrictMode's double mount: without it the second run
    // animates from the first run's end state and the hero never appears.
    return () => ctx.revert();
  }, [ready]);

  useEffect(() => {
    const id = window.setInterval(
      () => setMoodIndex((i) => (i + 1) % MOODS.length),
      2000,
    );
    return () => window.clearInterval(id);
  }, []);

  return (
    <section
      id="home"
      ref={root}
      className="relative flex min-h-[100svh] flex-col items-center justify-center overflow-hidden px-6 text-center"
    >
      <KenBurnsBackdrop />

      <div className="relative z-10 flex flex-col items-center">
        <p className="blur-in mb-8 text-xs uppercase tracking-[0.3em] text-muted">
          Cameroon · Edition &rsquo;26
        </p>

        <h1 className="name-reveal mb-6 font-display text-6xl italic leading-[0.9] tracking-tight text-text-primary md:text-8xl lg:text-9xl">
          Kamer-Go
        </h1>

        <p className="blur-in mb-6 text-lg text-text-primary/90 md:text-xl">
          Your next{" "}
          <span
            // Re-keying is what replays the CSS animation; React would
            // otherwise just swap the text inside a settled element.
            key={moodIndex}
            className="inline-block animate-role-fade-in font-display italic text-text-primary"
          >
            {MOODS[moodIndex]}
          </span>{" "}
          is twenty minutes away.
        </p>

        <p className="blur-in mb-12 max-w-md text-balance text-sm text-muted md:text-base">
          Discover the landmarks, culture and nature of Cameroon — with an
          itinerary planner that builds your day for you.
        </p>

        <div className="blur-in inline-flex flex-wrap items-center justify-center gap-4">
          <button
            type="button"
            onClick={() => scrollToSection("explore")}
            className="group relative rounded-full transition-transform duration-300 hover:scale-105"
          >
            <span
              className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
              style={{ inset: "-2px" }}
              aria-hidden="true"
            />
            <span className="relative block rounded-full bg-text-primary px-7 py-3.5 text-sm text-bg transition-colors duration-300 group-hover:bg-bg group-hover:text-text-primary">
              Start exploring
            </span>
          </button>

          <a
            href="/app/"
            className="group relative rounded-full transition-transform duration-300 hover:scale-105"
          >
            <span
              className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
              style={{ inset: "-2px" }}
              aria-hidden="true"
            />
            <span className="relative block rounded-full border-2 border-stroke bg-bg px-7 py-3.5 text-sm text-text-primary transition-colors duration-300 group-hover:border-transparent">
              Launch the web app ↗
            </span>
          </a>
        </div>
      </div>

      <div className="absolute inset-x-0 bottom-8 z-10 flex flex-col items-center gap-3">
        <span className="text-xs uppercase tracking-[0.2em] text-muted">
          Scroll
        </span>
        <span className="relative block h-10 w-px overflow-hidden bg-stroke">
          <span className="accent-gradient absolute inset-x-0 h-4 animate-scroll-down" />
        </span>
      </div>
    </section>
  );
}
