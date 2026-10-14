import { AnimatePresence, motion } from "framer-motion";
import { useCallback, useState } from "react";
import { Link, Route, Routes, useLocation } from "react-router-dom";

import LoadingScreen from "./components/LoadingScreen";
import Navbar from "./components/Navbar";
import Contact from "./sections/Contact";
import Explorations from "./sections/Explorations";
import Featured from "./sections/Featured";
import Guides from "./sections/Guides";
import Hero from "./sections/Hero";
import Stats from "./sections/Stats";

interface PageProps {
  ready: boolean;
}

function Landing({ ready }: PageProps) {
  return (
    <>
      <Hero ready={ready} />
      <Featured />
      <Guides />
      <Explorations />
      <Stats />
      <Contact />
    </>
  );
}

function NotFound() {
  return (
    <main className="flex min-h-[100svh] flex-col items-center justify-center gap-6 px-6 text-center">
      <p className="text-xs uppercase tracking-[0.3em] text-muted">404</p>
      <h1 className="font-display text-5xl italic text-text-primary md:text-7xl">
        Off the map
      </h1>
      <p className="max-w-sm text-balance text-sm text-muted">
        That page does not exist. The ones that do are all one scroll away.
      </p>
      <Link
        to="/"
        className="rounded-full bg-text-primary px-7 py-3.5 text-sm text-bg transition-transform duration-300 hover:scale-105"
      >
        Back to the start
      </Link>
    </main>
  );
}

export default function App() {
  const [loading, setLoading] = useState(true);
  const location = useLocation();

  const finish = useCallback(() => setLoading(false), []);

  return (
    <>
      <AnimatePresence>
        {loading && <LoadingScreen onComplete={finish} />}
      </AnimatePresence>

      <Navbar />

      {/* Keyed on pathname so a route change crossfades rather than snapping.
          mode="wait" keeps the outgoing page until its exit finishes, which
          stops the two from briefly stacking and doubling the page height. */}
      <AnimatePresence mode="wait">
        <motion.main
          key={location.pathname}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
        >
          <Routes location={location}>
            <Route path="/" element={<Landing ready={!loading} />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </motion.main>
      </AnimatePresence>
    </>
  );
}
