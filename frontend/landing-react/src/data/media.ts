/**
 * Every photograph on this page is a real place in Yaoundé (plus a handful of
 * the wider-Cameroon spots the app ships with), taken from the same library the
 * app itself uses: frontend/assets/images.
 *
 * In production nginx serves that folder at /media/, rsynced by the Jenkins
 * publish stage. In dev the Vite middleware in vite.config.ts maps the same
 * prefix onto the source folder, so these paths are correct in both places.
 *
 * Paths are written here unencoded and run through media() because a good third
 * of the library has spaces in its filename; an unencoded space in an <img src>
 * is a silent 404 behind nginx's `try_files $uri =404` asset rule.
 */
export function media(path: string): string {
  return `/media/${path.split("/").map(encodeURIComponent).join("/")}`;
}

export interface Slide {
  src: string;
  alt: string;
}

/** The hero backdrop: six wide, legible views of the city, crossfading. */
export const HERO_SLIDES: Slide[] = [
  {
    src: media("destinations/reunification-monument.jpg"),
    alt: "The Reunification Monument spiralling above Yaoundé",
  },
  {
    src: media("tourist/basilique marie reine.jpg"),
    alt: "Basilique Marie Reine des Apôtres, Mvolyé",
  },
  {
    src: media("destinations/mount-febe.jpg"),
    alt: "Mount Fébé looking out over the city",
  },
  {
    src: media("hilton yaounde pool-exterior.jpg"),
    alt: "The Hilton Yaoundé terrace at dusk",
  },
  {
    src: media("Yaounde Grand Mosque.webp"),
    alt: "The Grand Mosque of Yaoundé",
  },
  {
    src: media("destinations/yaounde.jpg"),
    alt: "Yaoundé spread across its seven hills",
  },
];

export interface Destination {
  title: string;
  kind: string;
  image: string;
  /** Tailwind column span on the md: breakpoint — the 7/5/5/7 bento rhythm. */
  span: string;
  aspect: string;
}

export const FEATURED: Destination[] = [
  {
    title: "Reunification Monument",
    kind: "Landmark · Ngoa-Ekellé",
    image: media("destinations/reunification-monument.jpg"),
    span: "md:col-span-7",
    aspect: "aspect-[16/11]",
  },
  {
    title: "Basilique Marie Reine",
    kind: "Culture · Mvolyé",
    image: media("tourist/basilique marie reine.jpg"),
    span: "md:col-span-5",
    aspect: "aspect-[16/11]",
  },
  {
    title: "Mvog-Betsi Zoo",
    kind: "Nature · Mvog-Betsi",
    image: media("destinations/mvog-betsi-zoo.jpg"),
    span: "md:col-span-5",
    aspect: "aspect-[16/11]",
  },
  {
    title: "National Museum",
    kind: "History · Centre-ville",
    image: media("destinations/national-museum.jpg"),
    span: "md:col-span-7",
    aspect: "aspect-[16/11]",
  },
];

export interface Guide {
  title: string;
  blurb: string;
  image: string;
  minutes: string;
  stops: string;
}

/** The reference's "Journal" row, carrying day-plans instead of blog posts. */
export const GUIDES: Guide[] = [
  {
    title: "A morning at Marché Central",
    blurb: "Fabric, fruit and the loudest hour in town.",
    image: media("dining/marche central yaounde.jpg"),
    minutes: "3 hr",
    stops: "4 stops",
  },
  {
    title: "Colonial Yaoundé on foot",
    blurb: "The cathedral, the post office and everything between.",
    image: media("cathedrale-nd-des-victoires.jpg"),
    minutes: "2 hr",
    stops: "5 stops",
  },
  {
    title: "Museums and the Ethnographic collection",
    blurb: "Where the country keeps its own story.",
    image: media("musee-ethnographique.jpg"),
    minutes: "4 hr",
    stops: "3 stops",
  },
  {
    title: "An evening in Bastos",
    blurb: "Rooftops, embassies and a very long dinner.",
    image: media("destinations/bastos-district.jpg"),
    minutes: "5 hr",
    stops: "6 stops",
  },
];

/** The parallax gallery — two columns of three, drifting at different rates. */
export const EXPLORATIONS: Slide[] = [
  {
    src: media("tourist/independence monument.jpg"),
    alt: "Independence Monument",
  },
  {
    src: media("leisure/piscine mont febe.jpg"),
    alt: "The pool on Mount Fébé",
  },
  {
    src: media("shopping/mokolo market.webp"),
    alt: "Mokolo market",
  },
  {
    src: media("tourist/i love my country cameroon monument.webp"),
    alt: "The I Love My Country monument",
  },
  {
    src: media("recreational/lake ossa.jpg"),
    alt: "Lake Ossa",
  },
  {
    src: media("tourist/city council.webp"),
    alt: "Yaoundé City Council",
  },
];
