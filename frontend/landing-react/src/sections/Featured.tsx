import { motion } from "framer-motion";

import GradientButton from "../components/GradientButton";
import SectionHeader from "../components/SectionHeader";
import { FEATURED } from "../data/media";

export default function Featured() {
  return (
    <section id="explore" className="bg-bg py-12 md:py-16">
      <div className="mx-auto max-w-[1200px] px-6 md:px-10 lg:px-16">
        <SectionHeader
          eyebrow="Selected places"
          lead="Featured"
          italic="destinations"
          subtext="A handful of the spots the app plans around — landmarks, culture and nature, all within reach of the city."
          action={
            <GradientButton href="/app/" className="hidden md:inline-flex">
              See all destinations
              <span aria-hidden="true">→</span>
            </GradientButton>
          }
        />

        <div className="grid grid-cols-1 gap-5 md:grid-cols-12 md:gap-6">
          {FEATURED.map((place, i) => (
            <motion.article
              key={place.title}
              initial={{ opacity: 0, y: 40 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.9,
                ease: [0.25, 0.1, 0.25, 1],
                delay: (i % 2) * 0.1,
              }}
              viewport={{ once: true, margin: "-80px" }}
              className={`group relative overflow-hidden rounded-3xl border border-stroke bg-surface ${place.span} ${place.aspect}`}
            >
              <img
                src={place.image}
                alt={place.title}
                loading="lazy"
                decoding="async"
                className="h-full w-full object-cover transition-transform duration-700 ease-out group-hover:scale-105"
              />

              <span
                className="halftone pointer-events-none absolute inset-0 opacity-20 mix-blend-multiply"
                aria-hidden="true"
              />

              {/* The caption sits on the photograph at rest so the grid is
                  readable without a pointer — a hover-only label would leave
                  touch users with four unlabelled rectangles. */}
              <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent p-6 transition-opacity duration-500 group-hover:opacity-0">
                <p className="text-xs uppercase tracking-[0.2em] text-white/60">
                  {place.kind}
                </p>
                <h3 className="mt-1 font-display text-2xl italic text-white md:text-3xl">
                  {place.title}
                </h3>
              </div>

              <div className="pointer-events-none absolute inset-0 flex items-center justify-center bg-bg/70 opacity-0 backdrop-blur-lg transition-opacity duration-500 group-hover:opacity-100">
                <span className="relative rounded-full p-[1.5px]">
                  <span
                    className="gradient-ring absolute inset-0 animate-gradient-shift rounded-full"
                    aria-hidden="true"
                  />
                  <span className="relative block rounded-full bg-white px-5 py-2.5 text-sm text-black">
                    View —{" "}
                    <span className="font-display italic">{place.title}</span>
                  </span>
                </span>
              </div>
            </motion.article>
          ))}
        </div>

        <GradientButton href="/app/" className="mt-8 md:hidden">
          See all destinations
          <span aria-hidden="true">→</span>
        </GradientButton>
      </div>
    </section>
  );
}
