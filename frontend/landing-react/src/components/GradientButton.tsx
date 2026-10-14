import type { ReactNode } from "react";

interface Props {
  /** Where the pill navigates. Omit it and pass [onClick] for an in-page
   *  action, which renders a real <button> instead of an anchor. */
  href?: string;
  onClick?: () => void;
  children: ReactNode;
  className?: string;
}

/** The pill's inner face. Shared so the anchor and button forms cannot drift. */
function Face({ children }: { children: ReactNode }) {
  return (
    <>
      <span
        className="gradient-ring absolute rounded-full opacity-0 transition-opacity duration-300 group-hover:animate-gradient-shift group-hover:opacity-100"
        style={{ inset: "-2px" }}
        aria-hidden="true"
      />
      <span className="relative inline-flex items-center gap-2 rounded-full border border-stroke bg-bg px-5 py-2.5 text-sm text-text-primary transition-colors duration-300 group-hover:border-transparent">
        {children}
      </span>
    </>
  );
}

/**
 * The page's one button treatment: a pill whose border becomes the accent
 * gradient on hover. The gradient is a span inset by -2px behind the content
 * rather than a real border, because a border cannot hold a gradient and
 * swapping border colours would shift the layout by the border width.
 *
 * An action with no destination is a `<button>`, not an `<a>`. Rendering it as
 * an anchor forces a choice between `href="#"`, which rewrites the URL and
 * hijacks the back button, and a link to a path that need not exist — which is
 * how "Open the gallery" came to point at a 404.
 */
export default function GradientButton({
  href,
  onClick,
  children,
  className,
}: Props) {
  const shell = `group relative inline-flex shrink-0 rounded-full ${className ?? ""}`;

  if (href === undefined) {
    return (
      <button type="button" onClick={onClick} className={shell}>
        <Face>{children}</Face>
      </button>
    );
  }

  return (
    <a href={href} onClick={onClick} className={shell}>
      <Face>{children}</Face>
    </a>
  );
}
