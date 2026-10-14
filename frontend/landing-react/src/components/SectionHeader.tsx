import { motion } from "framer-motion";
import type { ReactNode } from "react";

interface Props {
  eyebrow: string;
  /** Rendered as "{lead} {italic}" with the second word set in the display
   *  serif — the typographic signature the whole page is built around. */
  lead: string;
  italic: string;
  subtext: string;
  action?: ReactNode;
}

export default function SectionHeader({
  eyebrow,
  lead,
  italic,
  subtext,
  action,
}: Props) {
  return (
    <motion.header
      initial={{ opacity: 0, y: 30 }}
      whileInView={{ opacity: 1, y: 0 }}
      transition={{ duration: 1, ease: [0.25, 0.1, 0.25, 1] }}
      viewport={{ once: true, margin: "-100px" }}
      className="mb-10 flex flex-col gap-6 md:mb-14 md:flex-row md:items-end md:justify-between"
    >
      <div>
        <div className="mb-5 flex items-center gap-3">
          <span className="h-px w-8 bg-stroke" />
          <span className="text-xs uppercase tracking-[0.3em] text-muted">
            {eyebrow}
          </span>
        </div>

        <h2 className="text-4xl leading-[1.05] tracking-tight text-text-primary md:text-5xl lg:text-6xl">
          {lead} <span className="font-display italic">{italic}</span>
        </h2>

        <p className="mt-4 max-w-lg text-balance text-sm text-muted md:text-base">
          {subtext}
        </p>
      </div>

      {action}
    </motion.header>
  );
}
