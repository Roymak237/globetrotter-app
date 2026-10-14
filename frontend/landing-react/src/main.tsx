import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";

import App from "./App";
import "./index.css";

const root = document.getElementById("root");
if (!root) {
  throw new Error("#root is missing from index.html");
}

createRoot(root).render(
  <StrictMode>
    {/* nginx answers any unmatched path with index.html, so client-side routes
        survive a refresh and a deep link. */}
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
);
