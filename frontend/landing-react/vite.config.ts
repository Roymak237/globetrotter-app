import { createReadStream, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";

/**
 * In production the destination photography is served from /media/, which the
 * Jenkins publish stage rsyncs straight out of frontend/assets/images so the
 * filenames survive intact (the Flutter build percent-encodes them, which makes
 * them unusable from plain HTML).
 *
 * The dev server has no such stage, so this middleware maps the same URL prefix
 * onto the source folder. Without it every photo on the page is a 404 locally
 * and the layout can only be checked against empty boxes.
 */
const MEDIA_ROOT = resolve(__dirname, "../assets/images");

const MIME: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".avif": "image/avif",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
};

function serveMedia(): Plugin {
  return {
    name: "kamer-go-media",
    configureServer(server) {
      server.middlewares.use("/media", (req, res, next) => {
        const raw = decodeURIComponent((req.url ?? "/").split("?")[0]);

        // normalize() collapses any ../ before the prefix check, so a crafted
        // URL cannot walk out of the photo folder and read the repository.
        const target = normalize(join(MEDIA_ROOT, raw));
        if (!target.startsWith(MEDIA_ROOT)) {
          res.statusCode = 403;
          res.end("Forbidden");
          return;
        }

        try {
          if (!statSync(target).isFile()) {
            next();
            return;
          }
        } catch {
          next();
          return;
        }

        res.setHeader(
          "Content-Type",
          MIME[extname(target).toLowerCase()] ?? "application/octet-stream",
        );
        createReadStream(target).pipe(res);
      });
    },
  };
}

export default defineConfig({
  // The page is served from the document root, next to /app/ and /downloads/.
  base: "/",
  plugins: [react(), serveMedia()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    // Content-hashed filenames are what let nginx's revalidate-everything rule
    // stay cheap: a returning visitor re-downloads only what actually changed.
    assetsDir: "assets",
  },
  server: {
    port: 5273,
    // The landing page links to /app/, /api/ and /downloads/, which only exist
    // behind the deployed nginx. Proxying keeps those links live in dev.
    proxy: {
      "/api": "http://127.0.0.1:5000",
    },
  },
});
