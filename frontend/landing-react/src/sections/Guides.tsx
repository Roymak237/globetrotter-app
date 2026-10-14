import { motion } from "framer-motion";

import GradientButton from "../components/GradientButton";
import SectionHeader from "../components/SectionHeader";
import { GUIDES } from "../data/media";

export default function Guides() {
  return (
    <section id="guides" className="bg-bg py-16 md:py-24">
      <div className="mx-auto max-w-[1200px] px-6 md:px-10 lg:px-16">
        <SectionHeader
          eyebrow="Ready-made days"
          lead="Day"
          italic="itineraries"
          subtext="Pick a plan and go, or let the app build one around the hours you actually have."
          action={
            <GradientButton href="/app/" className="hidden md:inline-flex">
              Build your own
              <span aria-hidden="true">→</span>
            </GradientButton>
          }
        />

        <ul className="flex flex-col gap-4">
          {GUIDES.map((guide, i) => (
            <motion.li
              key={guide.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.7,
                ease: [0.25, 0.1, 0.25, 1],
                delay: i * 0.06,
              }}
              viewport={{ once: true, margin: "-60px" }}
            >
              <a
                href="/app/"
                className="group flex items-center gap-4 rounded-[40px] border border-stroke bg-surface/30 p-4 transition-colors duration-300 hover:bg-surface sm:gap-6 sm:rounded-full"
              >
                <img
                  src={guide.image}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="h-16 w-16 shrink-0 rounded-full object-cover transition-transform duration-500 group-hover:scale-105 sm:h-20 sm:w-20"
                />

                <div className="min-w-0 flex-1">
                  <h3 className="truncate text-base text-text-primary md:text-lg">
                    {guide.title}
                  </h3>
                  <p className="truncate text-sm text-muted">{guide.blurb}</p>
                </div>

                {/* Hidden rather than wrapped on narrow screens: the pill is
                    already tight at 320px and the same facts are on the
                    itinerary itself. */}
                <div className="hidden shrink-0 items-center gap-6 pr-4 text-sm text-muted sm:flex">
                  <span>{guide.minutes}</span>
                  <span>{guide.stops}</span>
                </div>

                <span
                  className="mr-2 shrink-0 text-muted transition-all duration-300 group-hover:translate-x-1 group-hover:text-text-primary"
                  aria-hidden="true"
                >
                  →
                </span>
              </a>
            </motion.li>
          ))}
        </ul>

        <GradientButton href="/app/" className="mt-8 md:hidden">
          Build your own
          <span aria-hidden="true">→</span>
        </GradientButton>
      </div>
    </section>
  );
}
