import { motion, useInView } from "framer-motion";
import { useEffect, useRef, useState } from "react";

/**
 * Counts up to `value` once the number is actually on screen. Driven by elapsed
 * time rather than a per-frame increment so the run takes the same 1.1s on a
 * 60Hz phone as on a 144Hz monitor.
 */
function useCountUp(value: number, active: boolean) {
  const [shown, setShown] = useState(0);

  useEffect(() => {
    if (!active) return;

    const DURATION = 1100;
    const start = performance.now();
    let frame = 0;

    const step = (now: number) => {
      const progress = Math.min((now - start) / DURATION, 1);
      // Ease-out cubic: quick off the mark, settling onto the final number.
      setShown(Math.round(value * (1 - Math.pow(1 - progress, 3))));
      if (progress < 1) frame = requestAnimationFrame(step);
    };

    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [value, active]);

  return shown;
}

interface StatProps {
  value?: number;
  suffix?: string;
  text?: string;
  label: string;
  active: boolean;
}

function Stat({ value, suffix, text, label, active }: StatProps) {
  const shown = useCountUp(value ?? 0, active && value !== undefined);

  return (
    <div className="border-t border-stroke pt-6">
      <p className="font-display text-5xl tabular-nums text-text-primary md:text-7xl">
        {text ?? `${shown}${suffix ?? ""}`}
      </p>
      <p className="mt-2 text-xs uppercase tracking-[0.2em] text-muted">
        {label}
      </p>
    </div>
  );
}

export default function Stats() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });

  // The catalogue grows between releases, so the headline number is read from
  // the API the app itself serves. The fallback is the count at time of
  // writing: a failed fetch should show a slightly stale figure, not a zero.
  const [destinations, setDestinations] = useState(57);

  useEffect(() => {
    const controller = new AbortController();

    fetch("/api/destinations", {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((payload: unknown) => {
        const list = Array.isArray(payload)
          ? payload
          : ((payload as { destinations?: unknown[] })?.destinations ?? []);
        if (list.length) setDestinations(list.length);
      })
      .catch(() => {
        /* Keep the fallback. */
      });

    return () => controller.abort();
  }, []);

  return (
    <section className="bg-bg py-16 md:py-24">
      <motion.div
        ref={ref}
        initial={{ opacity: 0, y: 30 }}
        whileInView={{ opacity: 1, y: 0 }}
        transition={{ duration: 1, ease: [0.25, 0.1, 0.25, 1] }}
        viewport={{ once: true, margin: "-100px" }}
        className="mx-auto grid max-w-[1200px] grid-cols-1 gap-10 px-6 sm:grid-cols-3 md:px-10 lg:px-16"
      >
        <Stat
          value={destinations}
          suffix="+"
          label="Curated spots"
          active={inView}
        />
        <Stat value={2} suffix="" label="Platforms" active={inView} />
        <Stat text="EN / FR" label="Fully bilingual" active={inView} />
      </motion.div>
    </section>
  );
}
