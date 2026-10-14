/** @type {import('tailwindcss').Config} */
export default {
  // Forced dark theme. There is no light mode and no toggle, so the `dark`
  // variant is never consulted and the palette below is the only one.
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "hsl(var(--bg))",
        surface: "hsl(var(--surface))",
        "text-primary": "hsl(var(--text))",
        muted: "hsl(var(--muted))",
        stroke: "hsl(var(--stroke))",
        accent: "hsl(var(--accent))",
      },
      fontFamily: {
        body: ["Inter", "system-ui", "sans-serif"],
        display: ["'Instrument Serif'", "Georgia", "serif"],
      },
      keyframes: {
        "scroll-down": {
          "0%": { transform: "translateY(-100%)" },
          "100%": { transform: "translateY(200%)" },
        },
        "role-fade-in": {
          "0%": { opacity: "0", transform: "translateY(8px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "gradient-shift": {
          "0%": { backgroundPosition: "0% 50%" },
          "50%": { backgroundPosition: "100% 50%" },
          "100%": { backgroundPosition: "0% 50%" },
        },
        // The hero slideshow replaces the reference's HLS video. Each slide
        // crossfades while drifting, so a still photograph reads as motion.
        "ken-burns": {
          "0%": { transform: "scale(1.06) translate3d(0, 0, 0)" },
          "100%": { transform: "scale(1.18) translate3d(-1.5%, -1.5%, 0)" },
        },
      },
      animation: {
        "scroll-down": "scroll-down 1.5s ease-in-out infinite",
        "role-fade-in": "role-fade-in 0.4s ease-out",
        "gradient-shift": "gradient-shift 6s ease infinite",
        "ken-burns": "ken-burns 9s ease-out forwards",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};
