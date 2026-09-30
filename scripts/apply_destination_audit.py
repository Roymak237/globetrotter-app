"""
scripts/apply_destination_audit.py

Rewrites backend/data/destinations.json so the destination pages say something
useful to a visitor.

Why this exists
---------------
An earlier verification pass stripped unsafe coordinates and images, which was
right, but it wrote its own working notes into `location_notes`, which the
detail screen prints verbatim. Users were reading sentences like "ID preserved
for itinerary references" and "Unverified coordinates removed; no pin." That is
a reviewer talking to another reviewer, not a travel app talking to a traveller.

This script replaces those notes with plain guidance, attaches the coordinates
found by scripts/geocode_destinations2.py, and fills in indicative daily costs
in CFA francs.

Three ideas keep it honest
--------------------------
1. `location_precision` says whether a pin is the venue itself ("exact") or the
   centre of its neighbourhood ("area"). Most of these businesses are known
   only by the quarter they sit in. A pin on Bastos is genuinely useful; the
   same pin pretending to be a restaurant door is a lie. The field lets the map
   say which one it is instead of hiding the difference.
2. `cost_notes` says where a number came from. The cost tile is already
   labelled "EST. DAILY COST", and these are category estimates, not surveyed
   prices, so each one carries a sentence admitting that.
3. Costs stay null where a daily cost is meaningless - schools and the district
   hospital. The app already renders "Not available" and leaves nulls out of
   itinerary totals, so null is a better answer than a made-up number.

Three records are deleted rather than patched. Each is a listing with no photo
whose subject could not be shown to exist at all. Keeping them meant showing a
blank card for a place nobody can visit.

Run from the repository root. Rewrites destinations.json and itineraries.json.
"""
import json
import shutil
from pathlib import Path

DESTINATIONS = Path("backend/data/destinations.json")
ITINERARIES = Path("backend/data/itineraries.json")


def osm(lat, lon):
    """A link a reader can open to check the pin themselves."""
    return f"https://www.openstreetmap.org/?mlat={lat}&mlon={lon}#map=17/{lat}/{lon}"


# Listings with no photo whose subject could not be shown to exist.
# The reason is recorded because deleting data should never be silent.
REMOVE = {
    "dest-yao-009": "Duplicate of dest-yao-003 National Museum, with no "
                    "separate identity, photo or location of its own.",
    "dest-yao-010": "No park in Cite Verte could be confirmed; the source "
                    "describes a residential quarter. No photo either.",
    "dest-yao-030": "No lake of this name exists. The Sanaga is a river, and "
                    "Lake Ossa (dest-yao-029) already covers a real lake.",
}

# id -> fields to write. Only the keys present are touched.
#
# "precision" is "exact" when the pin is the place itself, "area" when it is
# the centre of the surrounding quarter, and absent when there is no pin.
UPDATES = {
    # ---------------------------------------------------------------- city --
    "dest-yao-001": {
        "lat": 3.868987, "lon": 11.521334, "precision": "area",
        "notes": "The pin sits on the centre of Yaounde's urban community. "
                 "Use it to orient yourself, then open one of the individual "
                 "listings below for a specific place to visit.",
        "cost": 25000,
        "cost_notes": "Rough daily budget for one visitor covering local "
                      "transport, meals and small entry fees. Not a surveyed "
                      "figure.",
        "sources": ["https://en.wikipedia.org/wiki/Yaound%C3%A9"],
    },
    "dest-yao-002": {
        "precision": "exact",
        "notes": "The monument stands in the Centre Administratif district, "
                 "south-west of the city centre. It is an outdoor landmark, "
                 "visible and photographable from the surrounding square.",
        "cost": 0,
        "cost_notes": "Free to view from the square. Any guided tour or "
                      "interior access would be extra.",
    },
    "dest-yao-003": {
        "precision": "exact",
        "notes": "Housed in the former presidential palace on Rue 3.038 in "
                 "the Centre Administratif district. The pin is on the "
                 "building itself.",
        "cost": 2000,
        "cost_notes": "Typical museum admission for one adult. Check current "
                      "prices before travelling.",
    },
    "dest-yao-004": {
        "precision": "exact",
        "notes": "The pin marks the summit of the hill, not a trailhead or "
                 "car park. The hotel and its pool are separate listings "
                 "further down the slope.",
        "cost": 0,
        "cost_notes": "No charge for the hill itself. Budget for the taxi up "
                      "and back.",
    },
    "dest-yao-005": {
        "lat": 3.842149, "lon": 11.488817, "precision": "exact",
        "notes": "The Grand Marche de Biyem-Assi, on Avenue de Mvolye in "
                 "Yaounde VI. Busiest in the morning.",
        "cost": 0,
        "cost_notes": "Free to enter. Bring cash for whatever you buy.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.842149, 11.488817)],
    },
    "dest-yao-006": {
        "lat": 3.887857, "lon": 11.498443, "precision": "exact",
        "notes": "The Grande Mosquee on Rue 2.375 in the Tsinga quarter of "
                 "Yaounde II. It is an active place of worship, so dress "
                 "modestly and ask before entering or photographing.",
        "cost": 0,
        "cost_notes": "No admission charge.",
        "sources": [osm(3.887857, 11.498443)],
    },
    "dest-yao-007": {
        "precision": "exact",
        "notes": "The zoo-botanical park in Mvog-Betsi, south-west of the "
                 "centre. Allow a couple of hours.",
        "cost": 2000,
        "cost_notes": "Typical zoo admission for one adult. Confirm on "
                      "arrival.",
    },
    "dest-yao-008": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "notes": "Bastos is a residential and diplomatic quarter north of the "
                 "centre, known for restaurants and nightlife. The pin is the "
                 "middle of the quarter, not any single venue.",
        "cost": 0,
        "cost_notes": "Free to walk around. Spending depends on where you "
                      "stop.",
        "sources": ["https://fr.wikipedia.org/wiki/Bastos",
                    osm(3.894018, 11.510882)],
    },
    # ------------------------------------------------------------- country --
    "dest-cmr-001": {
        "precision": "exact",
        "notes": "The pin is the summit, reached on foot from Buea over one "
                 "to three days. Climbs are arranged through guides in Buea; "
                 "do not set out alone.",
        "cost": 30000,
        "cost_notes": "Indicative daily cost of a guided climb including "
                      "guide and porter fees. Operators vary widely.",
    },
    "dest-cmr-002": {
        "precision": "exact",
        "notes": "On the Morton Bay coast in Limbe, at the mouth of the Limbe "
                 "River. The pin is the garden, not a named gate.",
        "cost": 3000,
        "cost_notes": "Typical garden admission for one adult.",
    },
    "dest-cmr-003": {
        "precision": "exact",
        "notes": "The falls meet the Atlantic about 7 km south of Kribi. The "
                 "pin is the falls; boat trips are arranged on the beach "
                 "nearby.",
        "cost": 5000,
        "cost_notes": "Indicative cost of local access and a short boat trip. "
                      "Negotiated on the day.",
    },
    "dest-cmr-004": {
        "precision": "exact",
        "notes": "On the Nkam River at Ekom-Nkam village, near Melong in the "
                 "Moungo department. The final approach is a walk down to the "
                 "viewpoint.",
        "cost": 5000,
        "cost_notes": "Indicative site access and local guide cost.",
    },
    "dest-cmr-005": {
        "precision": "area",
        "notes": "The pin is a representative point inside the park, not an "
                 "entrance. Check current travel advice for the Far North "
                 "before planning a visit.",
        "cost": 20000,
        "cost_notes": "Indicative daily cost of park entry with a vehicle and "
                      "guide.",
    },
    "dest-cmr-006": {
        "precision": "exact",
        "notes": "The palace of the Bamum kingdom sits in the centre of "
                 "Foumban and houses a museum.",
        "cost": 3000,
        "cost_notes": "Typical palace and museum admission for one adult.",
    },
    # -------------------------------------------------------------- gaming --
    "dest-yao-011": {
        "lat": 3.875898, "lon": 11.543453, "precision": "area",
        "notes": "Known to be in Essos, in Yaounde V. The pin is the centre "
                 "of the quarter; ask locally for the exact street.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
        "sources": [osm(3.875898, 11.543453)],
    },
    "dest-yao-012": {
        "notes": "We only know this venue is in Yaounde, so there is no map "
                 "pin yet. Ask locally for directions.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
    },
    "dest-yao-013": {
        "notes": "We only know this venue is in Yaounde, so there is no map "
                 "pin yet. Ask locally for directions.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
    },
    "dest-yao-014": {
        "lat": 3.840470, "lon": 11.486478, "precision": "area",
        "notes": "Listed at Rond-point Express in Biyem-Assi, Yaounde VI. The "
                 "pin is the centre of Biyem-Assi; the roundabout is the "
                 "landmark to aim for.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.840470, 11.486478)],
    },
    "dest-yao-015": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "notes": "In the Bastos quarter of Yaounde I. The pin is the centre "
                 "of the quarter rather than the door.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
        "sources": [osm(3.894018, 11.510882)],
    },
    "dest-yao-016": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "image": "gaming/arcade game bastos.jpg",
        "notes": "An arcade in the Bastos quarter of Yaounde I. The pin is "
                 "the centre of the quarter rather than the door.",
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a "
                      "quoted price.",
        "sources": [osm(3.894018, 11.510882)],
    },
    # -------------------------------------------------------------- dining --
    "dest-yao-017": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "notes": "In the Bastos quarter of Yaounde I. The pin is the centre "
                 "of the quarter; call ahead for the exact street.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
        "sources": [osm(3.894018, 11.510882)],
    },
    "dest-yao-018": {
        "notes": "We only know this restaurant is in Yaounde, so there is no "
                 "map pin yet.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
    },
    "dest-yao-019": {
        "lat": 3.840470, "lon": 11.486478, "precision": "area",
        "image": "dining/restaurant biyemassi.jpg",
        "notes": "In the Biyem-Assi quarter of Yaounde VI. The pin is the "
                 "centre of the quarter rather than the door.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.840470, 11.486478)],
    },
    "dest-yao-020": {
        "notes": "The listing names the country but not a quarter, so there "
                 "is no map pin yet.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
    },
    "dest-yao-021": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "notes": "In the Bastos quarter of Yaounde I. The pin is the centre "
                 "of the quarter rather than the door.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
        "sources": [osm(3.894018, 11.510882)],
    },
    "dest-yao-033": {
        "lat": 3.894018, "lon": 11.510882, "precision": "area",
        "notes": "In the Bastos quarter of Yaounde I. The pin is the centre "
                 "of the quarter rather than the door.",
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were "
                      "not surveyed.",
        "sources": [osm(3.894018, 11.510882)],
    },
    # ------------------------------------------------------------- markets --
    "dest-yao-022": {
        "lat": 3.866318, "lon": 11.517807, "precision": "exact",
        "notes": "The Marche Central on Rue 1.075, in the commercial centre "
                 "of Yaounde I. Crowded and lively; watch your belongings.",
        "cost": 0,
        "cost_notes": "Free to enter. Bring cash for whatever you buy.",
        "sources": [osm(3.866318, 11.517807)],
    },
    "dest-yao-037": {
        "lat": 3.874691, "lon": 11.500193, "precision": "exact",
        "notes": "The Marche Mokolo on Rue 2.060, in the Mokolo quarter of "
                 "Yaounde II. One of the city's largest markets.",
        "cost": 0,
        "cost_notes": "Free to enter. Bring cash for whatever you buy.",
        "sources": ["https://fr.wikipedia.org/wiki/March%C3%A9_Mokolo",
                    osm(3.874691, 11.500193)],
    },
    # -------------------------------------------------------- supermarkets --
    "dest-yao-023": {
        "notes": "A Dovv branch associated with Tongolo. We could not confirm "
                 "the branch address, so there is no map pin yet.",
        "cost": 0,
        "cost_notes": "Free to enter. Spending depends on your shopping.",
    },
    "dest-yao-024": {
        "lat": 3.932829, "lon": 11.522330, "precision": "area",
        "notes": "A Dovv branch in Emana, northern Yaounde I. The pin is the "
                 "centre of the quarter rather than the shopfront.",
        "cost": 0,
        "cost_notes": "Free to enter. Spending depends on your shopping.",
        "sources": [osm(3.932829, 11.522330)],
    },
    "dest-yao-025": {
        "lat": 3.892521, "lon": 11.510106, "precision": "exact",
        "notes": "Dovv Bastos, on Rue 1.776 in Yaounde I. The pin is the shop "
                 "itself.",
        "cost": 0,
        "cost_notes": "Free to enter. Spending depends on your shopping.",
        "sources": [osm(3.892521, 11.510106)],
    },
    # ------------------------------------------------------ hotels, leisure --
    "dest-yao-026": {
        "lat": 3.912513, "lon": 11.495881, "precision": "exact",
        "notes": "The pool belongs to the Hotel Mont Febe on Rue 6.018, up "
                 "the Febe hill in Yaounde II. Ask the hotel whether "
                 "non-residents may swim.",
        "cost": 5000,
        "cost_notes": "Indicative day-pass cost for a hotel pool. Confirm "
                      "with the hotel.",
        "sources": ["https://www.hotel-montfebe.cm/",
                    osm(3.912513, 11.495881)],
    },
    "dest-yao-027": {
        "lat": 3.840470, "lon": 11.486478, "precision": "area",
        "image": "leisure/hotel biyemassi.jpg",
        "notes": "A hotel in the Biyem-Assi quarter of Yaounde VI. The pin is "
                 "the centre of the quarter; we could not confirm which hotel "
                 "or its street.",
        "cost": 25000,
        "cost_notes": "Indicative nightly rate for a mid-range room. Rates "
                      "were not confirmed with the property.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.840470, 11.486478)],
    },
    "dest-yao-034": {
        "lat": 3.912513, "lon": 11.495881, "precision": "exact",
        "notes": "On Rue 6.018 up the Febe hill in Yaounde II, overlooking "
                 "the city. Postal contact is BP 711.",
        "cost": 60000,
        "cost_notes": "Indicative nightly rate for a room at this hotel. "
                      "Confirm current rates when booking.",
        "sources": ["https://www.hotel-montfebe.cm/",
                    osm(3.912513, 11.495881)],
    },
    # --------------------------------------------------------------- parks --
    "dest-yao-028": {
        "lat": 3.862809, "lon": 11.478260, "precision": "area",
        "notes": "In the Mvog-Betsi quarter of Yaounde VI. The pin is the "
                 "centre of the quarter. The zoo-botanical park nearby is a "
                 "separate listing.",
        "cost": 1000,
        "cost_notes": "Indicative entry for a public park. Some are free.",
        "sources": ["https://en.wikipedia.org/wiki/Mvog-Betsi_Zoo",
                    osm(3.862809, 11.478260)],
    },
    "dest-yao-035": {
        "lat": 3.840470, "lon": 11.486478, "precision": "area",
        "notes": "A green space in the Biyem-Assi quarter of Yaounde VI. The "
                 "pin is the centre of the quarter; we could not confirm a "
                 "named park.",
        "cost": 1000,
        "cost_notes": "Indicative entry for a public park. Some are free.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.840470, 11.486478)],
    },
    "dest-yao-038": {
        "lat": 3.910524, "lon": 11.498987, "precision": "exact",
        "region": "Centre",
        "notes": "The Parcours Vita is a public exercise trail on the Febe "
                 "hill in Yaounde II, popular on weekend mornings.",
        "cost": 0,
        "cost_notes": "Free to use.",
        "sources": [osm(3.910524, 11.498987)],
    },
    "dest-yao-036": {
        "notes": "We have not confirmed which monument this photograph shows "
                 "or which city it is in, so there is no map pin yet. The "
                 "Reunification Monument is listed separately.",
        "cost": 0,
        "cost_notes": "Outdoor monuments are normally free to view.",
    },
    # ------------------------------------------------------- other Yaounde --
    "dest-yao-029": {
        "precision": "exact",
        "notes": "Lake Ossa lies west of Edea in the Littoral region, near "
                 "Dizangue. The pin is the lake itself, not a shore access "
                 "point; arrange a boat in Dizangue.",
        "cost": 5000,
        "cost_notes": "Indicative cost of local access and a boat trip.",
    },
    "dest-yao-031": {
        "precision": "exact",
        "notes": "The basilica stands on Mvolye hill in southern Yaounde, "
                 "with a wide view over the city. It is an active church.",
        "cost": 0,
        "cost_notes": "No admission charge.",
    },
    "dest-yao-032": {
        "lat": 3.834088, "lon": 11.485016, "precision": "exact",
        "region": "Centre",
        "notes": "The district hospital on Rue du Cafeier in Biyem-Assi, "
                 "Yaounde VI. This is a healthcare facility, listed so you "
                 "can find it in an emergency, not an attraction.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply. Treatment charges "
                      "depend entirely on the care you need.",
        "sources": ["https://fr.wikipedia.org/wiki/Biyem-Assi",
                    osm(3.834088, 11.485016)],
    },
    # ------------------------------------------------------------- schools --
    "dest-school-001": {
        "lat": 4.063812, "lon": 9.740959, "precision": "area",
        "notes": "The official contact page gives a main campus at Makepe "
                 "Carrefour Koppa Cabana in Douala, opposite Direction "
                 "Orange. The pin is the centre of Makepe.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://aimtinstitute.com/contact",
                    osm(4.063812, 9.740959)],
    },
    "dest-school-002": {
        "lat": 3.869594, "lon": 11.446827, "precision": "exact",
        "notes": "The campus is on Rue 6.538 in Nkolbisson, Yaounde VII. "
                 "Postal contact is BP 11628.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://www.ucac-icy.net/", osm(3.869594, 11.446827)],
    },
    "dest-school-003": {
        "lat": 3.932829, "lon": 11.522330, "precision": "area",
        "notes": "The official contact page gives Emana pont, Yaounde. The "
                 "pin is the centre of Emana.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://esmata.com/contact/", osm(3.932829, 11.522330)],
    },
    "dest-school-004": {
        "lat": 3.857117, "lon": 11.483427, "precision": "exact",
        "notes": "The bilingual secondary school on Rue 7.029, between "
                 "Etoug-Ebe and Mvog-Betsi in Yaounde VI.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a school. "
                      "Contact the school about fees.",
        "sources": ["https://fr.wikipedia.org/wiki/Etoug-Ebe",
                    osm(3.857117, 11.483427)],
    },
    "dest-school-005": {
        "notes": "We could not confirm this institution's campus address, so "
                 "there is no map pin yet.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
    },
    "dest-school-006": {
        "notes": "The university refers to a Zoatupsi campus in Yaounde, but "
                 "we have not been able to place it on the map yet.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://ictuniversity.org/"],
    },
    "dest-school-007": {
        "lat": 3.886458, "lon": 11.534189, "precision": "exact",
        "notes": "The Institut Universitaire des Sciences et Technologies de "
                 "Yaounde, on Rue 1.500. The institution lists more than one "
                 "campus, so confirm which one you need.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://www.facebook.com/IUSTYofficiel/",
                    osm(3.886458, 11.534189)],
    },
    "dest-school-008": {
        "notes": "We have not confirmed which school this is or which city it "
                 "is in, so there is no map pin yet.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a school. "
                      "Contact the school about fees.",
    },
    "dest-school-009": {
        "lat": 3.864356, "lon": 11.456249, "precision": "exact",
        "notes": "On Rue 6.513 in Nkolbisson, Yaounde VII. This is the lycee, "
                 "not the separate Lycee Technique in the same quarter.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a school. "
                      "Contact the school about fees.",
        "sources": ["https://fr.wikipedia.org/wiki/Nkolbisson",
                    osm(3.864356, 11.456249)],
    },
    "dest-school-010": {
        "precision": "exact",
        "notes": "In Ngoa Ekele, Yaounde III. Not to be confused with the "
                 "school of the same name in Saverne, France.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a school. "
                      "Contact the school about fees.",
    },
    "dest-school-011": {
        "lat": 5.728226, "lon": 10.897160, "precision": "area",
        "notes": "In Foumban, in the Noun department of the West region. The "
                 "pin is the centre of the town; we could not confirm the "
                 "campus address.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a school. "
                      "Contact the school about fees.",
        "sources": ["https://fr.wikipedia.org/wiki/Foumban",
                    osm(5.728226, 10.897160)],
    },
    "dest-school-012": {
        "lat": 3.856624, "lon": 11.499981, "precision": "exact",
        "notes": "The university is in Ngoa Ekele, off Rue Tsoungui Akoa. The "
                 "pin is the main campus; the medical faculty is one building "
                 "within it, so ask at the gate.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the faculty about tuition.",
        "sources": ["https://uy1.uninet.cm/faculte-de-medecine-et-des-sciences-biomedicales/",
                    "https://fr.wikipedia.org/wiki/Universit%C3%A9_de_Yaound%C3%A9_I",
                    osm(3.856624, 11.499981)],
    },
    "dest-school-013": {
        "lat": 3.978180, "lon": 11.593129, "precision": "area",
        "notes": "The university is at Soa, north-east of Yaounde. The pin is "
                 "the centre of Soa; postal contact is BP 18 Soa.",
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. "
                      "Contact the institution about tuition.",
        "sources": ["https://site.univ-yaounde2.org/",
                    osm(3.978180, 11.593129)],
    },
}

# The `address` field was written in the same reviewer's voice as the notes
# ("Bastos (filename only), Yaounde (legacy listing); exact address
# unverified") and is printed straight onto the page under the heading
# "Address". These replace it with something a taxi driver could use, or with
# the plain admission that we only know the quarter.
ADDRESSES = {
    "dest-yao-001": "Yaounde, Centre, Cameroon",
    "dest-yao-002": "Centre Administratif, Yaounde III, Centre, Cameroon",
    "dest-yao-003": "Rue 3.038, Centre Administratif, Yaounde III, Cameroon",
    "dest-yao-004": "Mont Febe, north-west of Yaounde, Centre, Cameroon",
    "dest-yao-005": "Avenue de Mvolye, Biyem-Assi, Yaounde VI, Cameroon",
    "dest-yao-006": "Rue 2.375, Tsinga, Yaounde II, Cameroon",
    "dest-yao-007": "Mvog-Betsi, Yaounde VI, Centre, Cameroon",
    "dest-yao-008": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-011": "Essos, Yaounde V, Centre, Cameroon",
    "dest-yao-012": "Yaounde, Centre, Cameroon (exact street unknown)",
    "dest-yao-013": "Yaounde, Centre, Cameroon (exact street unknown)",
    "dest-yao-014": "Rond-point Express, Biyem-Assi, Yaounde VI, Cameroon",
    "dest-yao-015": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-016": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-017": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-018": "Yaounde, Centre, Cameroon (exact street unknown)",
    "dest-yao-019": "Biyem-Assi, Yaounde VI, Centre, Cameroon",
    "dest-yao-020": "Cameroon (city and street unknown)",
    "dest-yao-021": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-022": "Rue 1.075, Centre Commercial, Yaounde I, Cameroon",
    "dest-yao-023": "Tongolo, Yaounde, Centre, Cameroon (branch street unknown)",
    "dest-yao-024": "Emana, Yaounde I, Centre, Cameroon",
    "dest-yao-025": "Rue 1.776, Bastos, Yaounde I, Cameroon",
    "dest-yao-026": "Hotel Mont Febe, Rue 6.018, Febe, Yaounde II, Cameroon",
    "dest-yao-027": "Biyem-Assi, Yaounde VI, Centre, Cameroon",
    "dest-yao-028": "Mvog-Betsi, Yaounde VI, Centre, Cameroon",
    "dest-yao-029": "Lake Ossa, near Dizangue, west of Edea, Littoral, Cameroon",
    "dest-yao-031": "Mvolye hill, Yaounde III, Centre, Cameroon",
    "dest-yao-032": "Rue du Cafeier, Biyem-Assi, Yaounde VI, Cameroon",
    "dest-yao-033": "Bastos, Yaounde I, Centre, Cameroon",
    "dest-yao-034": "Rue 6.018, Febe, Yaounde II, Cameroon (BP 711)",
    "dest-yao-035": "Biyem-Assi, Yaounde VI, Centre, Cameroon",
    "dest-yao-036": "Cameroon (city and site not yet confirmed)",
    "dest-yao-037": "Rue 2.060, Mokolo, Yaounde II, Cameroon",
    "dest-yao-038": "Febe, Yaounde II, Centre, Cameroon",
    "dest-cmr-001": "Mount Cameroon, near Buea, Southwest, Cameroon",
    "dest-cmr-002": "Morton Bay, Limbe, Fako, Southwest, Cameroon",
    "dest-cmr-003": "About 7 km south of Kribi, South, Cameroon",
    "dest-cmr-004": "Ekom-Nkam village, near Melong, Moungo, Littoral, Cameroon",
    "dest-cmr-005": "Waza, Logone-et-Chari, Far North, Cameroon",
    "dest-cmr-006": "Royal Palace, Foumban, Noun, West, Cameroon",
    "dest-school-001": "Makepe Carrefour Koppa Cabana, opposite Direction "
                       "Orange, Douala, Littoral, Cameroon",
    "dest-school-002": "Rue 6.538, Nkolbisson, Yaounde VII, Cameroon (BP 11628)",
    "dest-school-003": "Emana pont, Yaounde I, Centre, Cameroon",
    "dest-school-004": "Rue 7.029, Etoug-Ebe, Yaounde VI, Cameroon",
    "dest-school-005": "Yaounde, Centre, Cameroon (campus address unknown)",
    "dest-school-006": "Zoatupsi campus, Yaounde, Centre, Cameroon",
    "dest-school-007": "Rue 1.500, Yaounde, Centre, Cameroon",
    "dest-school-008": "Cameroon (city and campus not yet confirmed)",
    "dest-school-009": "Rue 6.513, Nkolbisson, Yaounde VII, Cameroon",
    "dest-school-010": "Ngoa Ekele, Yaounde III, Centre, Cameroon",
    "dest-school-011": "Foumban, Noun, West, Cameroon (campus street unknown)",
    "dest-school-012": "Rue Tsoungui Akoa, Ngoa Ekele, Yaounde III, Cameroon",
    "dest-school-013": "Soa, Mefou-et-Afamba, Centre, Cameroon (BP 18 Soa)",
}

# `description` is the "Why go" paragraph on the detail page, and it was
# written in the same voice as the notes: "Provisional gaming venue identified
# only by the supplied Game Lounge Essos filename." A traveller does not care
# how the record was sourced. Where we genuinely know little, these say what
# kind of place it is and leave it there.
DESCRIPTIONS = {
    "dest-yao-011": "A gaming lounge in Essos, on the eastern side of "
                    "Yaounde.",
    "dest-yao-012": "A gaming venue in Yaounde. We have not been able to "
                    "confirm which part of the city it is in.",
    "dest-yao-013": "A gaming lounge in Yaounde. We have not been able to "
                    "confirm which part of the city it is in.",
    "dest-yao-014": "A gaming centre by the Rond-point Express in Biyem-Assi.",
    "dest-yao-015": "A gaming venue in the Bastos quarter of Yaounde.",
    "dest-yao-016": "An arcade in Bastos. We know the quarter but not the "
                    "street.",
    "dest-yao-017": "A restaurant in Bastos, the diplomatic quarter north of "
                    "the city centre.",
    "dest-yao-018": "A restaurant in Yaounde. We have not been able to "
                    "confirm which part of the city it is in.",
    "dest-yao-019": "A restaurant in Biyem-Assi, in the south-west of "
                    "Yaounde.",
    "dest-yao-020": "A restaurant in Cameroon. We have not been able to "
                    "confirm the town it is in.",
    "dest-yao-021": "A restaurant in the Bastos quarter of Yaounde.",
    "dest-yao-022": "Yaounde's central market, in the commercial heart of the "
                    "city. Busy, covered and good for fabric, food and "
                    "household goods.",
    "dest-yao-023": "A branch of the Dovv supermarket chain, associated with "
                    "Tongolo in northern Yaounde.",
    "dest-yao-024": "A branch of the Dovv supermarket chain in Emana, "
                    "northern Yaounde.",
    "dest-yao-025": "A branch of the Dovv supermarket chain on Rue 1.776 in "
                    "Bastos.",
    "dest-yao-027": "A hotel in Biyem-Assi, in the south-west of Yaounde. We "
                    "know the quarter but not the street.",
    "dest-yao-028": "A green space in the Mvog-Betsi quarter. The "
                    "zoo-botanical park of the same neighbourhood is listed "
                    "separately.",
    "dest-yao-033": "A restaurant in the Bastos quarter of Yaounde.",
    "dest-yao-035": "A green space in Biyem-Assi, in the south-west of "
                    "Yaounde.",
    "dest-yao-036": "A monument photographed in Cameroon. We have not yet "
                    "confirmed which monument it is or where it stands.",
    "dest-yao-038": "A public exercise trail on the Febe hill, busy with "
                    "runners and walkers on weekend mornings.",
    "dest-school-005": "A higher education institute in Yaounde.",
    "dest-school-006": "A university with a campus in Yaounde.",
    "dest-school-008": "A secondary school in Cameroon. We have not yet "
                       "confirmed which town it is in.",
    "dest-school-011": "A technical secondary school in Foumban, in the West "
                       "region.",
}


def main():
    destinations = json.loads(DESTINATIONS.read_text(encoding="utf-8"))

    kept, removed = [], []
    for dest in destinations:
        if dest["id"] in REMOVE:
            removed.append(dest)
            continue
        kept.append(dest)

    # Both checks run before anything is written. A half-rewritten data file
    # is worse than a failed run.
    unknown = sorted(set(UPDATES) - {d["id"] for d in kept})
    if unknown:
        raise SystemExit(f"UPDATES names ids that do not exist: {unknown}")

    untouched = [d["id"] for d in kept if d["id"] not in UPDATES]
    if untouched:
        raise SystemExit(
            "every surviving destination needs a patch, or it keeps its old "
            f"audit notes. Missing: {untouched}")

    unaddressed = [d["id"] for d in kept if d["id"] not in ADDRESSES]
    if unaddressed:
        raise SystemExit(
            "every surviving destination needs an address, or it keeps the "
            f"old reviewer's wording. Missing: {unaddressed}")

    shutil.copy(DESTINATIONS, DESTINATIONS.with_suffix(".json.bak"))

    for dest in kept:
        dest["address"] = ADDRESSES[dest["id"]]
        if dest["id"] in DESCRIPTIONS:
            dest["description"] = DESCRIPTIONS[dest["id"]]
        patch = UPDATES.get(dest["id"])
        if patch is None:
            continue
        if "lat" in patch:
            dest["latitude"] = patch["lat"]
            dest["longitude"] = patch["lon"]
        if "precision" in patch:
            dest["location_precision"] = patch["precision"]
        if "region" in patch:
            dest["region"] = patch["region"]
        if "image" in patch:
            dest["image_asset"] = patch["image"]
        if "sources" in patch:
            dest["location_sources"] = patch["sources"]
        dest["location_notes"] = patch["notes"]
        dest["avg_cost_per_day"] = patch["cost"]
        dest["cost_notes"] = patch["cost_notes"]
        dest.setdefault("location_precision", "")

    for dest in kept:
        dest.setdefault("location_precision", "")
        dest.setdefault("cost_notes", "")

    DESTINATIONS.write_text(
        json.dumps(kept, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # Saved itineraries store destination ids as plain strings, so a deleted
    # id would linger as a stop that resolves to nothing.
    itineraries = json.loads(ITINERARIES.read_text(encoding="utf-8"))
    repaired = 0
    for itinerary in itineraries:
        stops = itinerary.get("destinations", [])
        pruned = [s for s in stops if s not in REMOVE]
        if len(pruned) != len(stops):
            itinerary["destinations"] = pruned
            itinerary["visited_stops"] = [
                s for s in itinerary.get("visited_stops", []) if s in pruned
            ]
            repaired += 1
    if repaired:
        ITINERARIES.write_text(
            json.dumps(itineraries, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8")

    pinned = sum(1 for d in kept if d.get("latitude") is not None)
    exact = sum(1 for d in kept if d.get("location_precision") == "exact")
    area = sum(1 for d in kept if d.get("location_precision") == "area")
    priced = sum(1 for d in kept if d.get("avg_cost_per_day") is not None)
    imageless = sum(1 for d in kept
                    if not d.get("image_asset") and not d.get("image_url"))

    print(f"removed {len(removed)}: " +
          ", ".join(f"{d['id']} ({d['name']})" for d in removed))
    for dest in removed:
        print(f"    {dest['id']}: {REMOVE[dest['id']]}")
    print(f"kept {len(kept)}")
    print(f"  pinned          {pinned}  ({exact} exact, {area} area-level)")
    print(f"  priced          {priced}")
    print(f"  no photo at all {imageless}")
    print(f"  itineraries repaired {repaired}")


if __name__ == "__main__":
    main()
