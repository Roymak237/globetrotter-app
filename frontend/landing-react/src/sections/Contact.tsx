import gsap from "gsap";
import { useEffect, useRef } from "react";

import { HERO_SLIDES, media } from "../data/media";

const MARQUEE = "SEVEN HILLS · ONE PLAN · ";
const LINKS = [
  { label: "Web app", href: "/app/" },
  { label: "Android APK", href: "/downloads/kamer-go.apk" },
  { label: "API", href: "/api/destinations" },
];

export default function Contact() {
  const track = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      // The strip holds two identical halves, so moving it exactly -50% lands
      // the second half where the first started and the loop has no seam.
      gsap.to(track.current, {
        xPercent: -50,
        duration: 40,
        ease: "none",
        repeat: -1,
      });
    }, track);

    return () => ctx.revert();
  }, []);

  return (
    <footer
      id="contact"
      className="relative overflow-hidden bg-bg pb-8 pt-16 md:pb-12 md:pt-20"
    >
      {/* The reference flips its hero video vertically here. Same idea, same
          photograph, so the page closes on the frame it opened with. */}
      <div className="absolute inset-0" aria-hidden="true">
        <img
          src={media("destinations/mount-febe.jpg")}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-full w-full scale-y-[-1] object-cover"
        />
        <div className="absolute inset-0 bg-black/70" />
        <div className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-bg to-transparent" />
      </div>

      <div className="relative z-10">
        <div className="overflow-hidden py-6">
          <div ref={track} className="flex w-max whitespace-nowrap">
            {[0, 1].map((half) => (
              <span
                key={half}
                className="font-display text-5xl italic text-text-primary/25 md:text-8xl"
                aria-hidden={half === 1}
              >
                {MARQUEE.repeat(10)}
              </span>
            ))}
          </div>
        </div>

        <div className="mx-auto max-w-[1200px] px-6 py-12 text-center md:px-10 md:py-20 lg:px-16">
          <p className="mb-5 text-xs uppercase tracking-[0.3em] text-muted">
            Ready when you are
          </p>

          <h2 className="mx-auto max-w-2xl text-balance text-4xl leading-[1.05] tracking-tight text-text-primary md:text-6xl">
            Plan your day in{" "}
            <span className="font-display italic">Cameroon</span>
          </h2>

          <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
            <a
              href="/app/"
              className="group relative rounded-full transition-transform duration-300 hover:scale-105"
            >
              <span
                className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
                style={{ inset: "-2px" }}
                aria-hidden="true"
              />
              <span className="relative block rounded-full bg-text-primary px-7 py-3.5 text-sm text-bg transition-colors duration-300 group-hover:bg-bg group-hover:text-text-primary">
                Launch the web app
              </span>
            </a>

            <a
              href="/downloads/kamer-go.apk"
              download
              className="group relative rounded-full transition-transform duration-300 hover:scale-105"
            >
              <span
                className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
                style={{ inset: "-2px" }}
                aria-hidden="true"
              />
              <span className="relative block rounded-full border-2 border-stroke bg-bg/80 px-7 py-3.5 text-sm text-text-primary backdrop-blur-md transition-colors duration-300 group-hover:border-transparent">
                Download for Android
              </span>
            </a>
          </div>
        </div>

        <div className="mx-auto flex max-w-[1200px] flex-col items-center gap-6 border-t border-stroke px-6 pt-8 text-sm text-muted md:flex-row md:justify-between md:px-10 lg:px-16">
          <div className="flex items-center gap-3">
            <img
              src="/app-icon-192.jpg"
              width={32}
              height={32}
              alt=""
              loading="lazy"
              decoding="async"
              className="h-8 w-8 rounded-full"
            />
            <span className="text-text-primary">Kamer-Go</span>
            <span className="hidden sm:inline">Built for Cameroon.</span>
          </div>

          <nav aria-label="Footer" className="flex flex-wrap gap-6">
            {LINKS.map((link) => (
              <a
                key={link.label}
                href={link.href}
                className="transition-colors duration-200 hover:text-text-primary"
              >
                {link.label}
              </a>
            ))}
          </nav>

          <div className="flex items-center gap-2">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-70" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-400" />
            </span>
            <span>All systems live</span>
          </div>
        </div>

        <p className="mt-8 text-center text-xs text-muted">
          © {new Date().getFullYear()} Kamer-Go · {HERO_SLIDES.length} views of
          a city worth the trip
        </p>
      </div>
    </footer>
  );
}
