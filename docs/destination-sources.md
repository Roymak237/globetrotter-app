# Destination evidence and image inventory

Research and audit date: 2026-09-16.

Scope: [destination data](../backend/data/destinations.json) and this document only. No frontend, Python, image, or itinerary files were edited.

## Results and interpretation

- **57 destinations:** all **38 original IDs and names preserved**, plus **19 new records** (6 places/site labels and 13 educational institutions).
- **57 local image files inventoried:** **44 assigned exactly once** across **42 primary-image records** and **2 additional images**; **13 unresolved files deliberately unassigned**.
- **18 case-sensitive Schools assets:** 13 linked, 5 unresolved. The directory is `Schools`, not `schools`.
- **13 records have source-published coordinates**; **44 have no latitude or longitude**. Published monument/campus points are not certified entrances. Summit, waterbody and park coordinates are explicitly identified as such.
- **35 records cite 31 distinct fetched URLs**. This is **not** a claim that 35 venues or photographs were independently verified: some citations establish only a neighborhood, parent institution, city, or conflicting identity. **22 records have empty source arrays**, not invented citations.
- All **57 daily costs are null**. No current average daily spending was established. Tuition, hotel room rates and admission fees are not interchangeable with an average daily cost. Unknown is not free.

### Evidence rules

`location_sources` contains only URLs whose content was actually fetched during this audit. Failed requests, bot challenges and unrelated namesakes are not positive evidence. Each record's `location_notes` explains what its sources establish and what remains unknown. A verified neighborhood or postal contact never supplies an exact venue pin.

Filename-only entries are provisional, not independently verified businesses or institutions. Legacy generic entries remain because itinerary references exist; keeping an ID is not confirmation that its advertised place exists. New named filename associations are explicitly marked when verification was unavailable. No facilities, cuisine, equipment, tournaments, access conditions or prices were inferred from a name.

### Photo provenance is separate from location evidence

**Creator, license, original download URL and authenticity of all 57 local assets are unknown.** A filename-to-place association is not visual authentication or proof that the image depicts the published address. This audit inventoried filenames and SHA-256 hashes; it did not establish visual identity or perform reverse-image verification. AIMT's conflicting city label and multi-campus institutions particularly need photo-owner confirmation.

Wikimedia Commons or Pexels credits inherited with remote images do **not** license or attribute the local files. For records retaining a remote fallback and a local image, the attribution explicitly separates **local creator/license unverified** from **remote fallback only, inherited credit**. Remote-only credits were preserved as inherited metadata, not reverified in this audit. Location articles are not photo-source evidence.

There are **no byte-identical files by SHA-256**. The two `additional_image_assets` entries group filename variants naming an already represented destination, not duplicate bytes or invented new places:

- Yaounde Central Market: French name plus misspelled English `central markey` name.
- Reunification Monument: two variants of the same monument label. Association follows the existing Yaounde record and collection context; the filenames alone do not rule out a different city's reunification monument. Obtain visual confirmation before treating either local image as authenticated evidence.

The less specific `parc mvogbetsi` label was **not** automatically merged into the zoo, and `yaounde meseum` was **not** automatically treated as a second National Museum photograph.

## Fetched evidence register

The following are paraphrased observations from actual successful fetches (browser extraction or read-only PowerShell HTTP requests), not claims about sources that were merely suggested by a search result.

### Published coordinates

Decimal values below are copied from the source or converted from its degrees/minutes/seconds notation, rounded to six decimals when needed. They are source-published locations, not field-surveyed coordinates or navigation/access guarantees.

| Destination ID | Fetched source | Evidence used | Latitude, longitude |
| --- | --- | --- | --- |
| dest-yao-002 | [Reunification Monument](https://en.wikipedia.org/wiki/Reunification_Monument) | Yaounde monument; GeoHack parameters explicitly give decimal coordinates. Unsupported Constitution Square claim removed. | 3.85246, 11.51343 |
| dest-yao-003 | [Musee national du Cameroun](https://fr.wikipedia.org/wiki/Mus%C3%A9e_national_du_Cameroun) | Former presidential palace in Yaounde; 3°51′37″ N, 11°30′56″ E. | 3.860278, 11.515556 |
| dest-yao-004 | [Mont Febe](https://fr.wikipedia.org/wiki/Mont_F%C3%A9b%C3%A9) | Hill near Yaounde; summit 3°54′50″ N, 11°29′20″ E, not hotel or pool. | 3.913889, 11.488889 |
| dest-yao-007 | [Mvog-Betsi Zoo](https://en.wikipedia.org/wiki/Mvog-Betsi_Zoo) | Parc zoo-botanique de Mvog Betsi in Yaounde; explicit decimal coordinates. | 3.8649, 11.48751 |
| dest-yao-029 | [Lake Ossa](https://en.wikipedia.org/wiki/Lake_Ossa) | Lake west of Edea, **Littoral**, with fishing/community links to Dizangue. Waterbody coordinate, not shore access. | 3.796663, 10.024779 |
| dest-yao-031 | [Mvolye basilica](https://fr.wikipedia.org/wiki/Basilique_Marie-Reine-des-Ap%C3%B4tres_de_Mvoly%C3%A9) | Mvolye hill, southern Yaounde; 3°50′33″ N, 11°30′28″ E. | 3.8425, 11.507778 |
| dest-cmr-001 | [Mount Cameroon](https://en.wikipedia.org/wiki/Mount_Cameroon) | Active volcano near Buea, Southwest; summit 4°13′00″ N, 9°10′21″ E, not a trailhead. | 4.216667, 9.1725 |
| dest-cmr-002 | [Limbe Botanic Garden](https://en.wikipedia.org/wiki/Limbe_Botanic_Garden) | Morton Bay at the Limbe River mouth; explicit decimal garden coordinate. | 4.0134, 9.212 |
| dest-cmr-003 | [Chutes de la Lobe](https://fr.wikipedia.org/wiki/Chutes_de_la_Lob%C3%A9) | About 7 km south of Kribi; 2°52′53″ N, 9°53′52″ E. | 2.881389, 9.897778 |
| dest-cmr-004 | [Chutes d'Ekom](https://fr.wikipedia.org/wiki/Chutes_d%27Ekom) | Ekom-Nkam village near Melong, Moungo, **Littoral rather than West**; 5°03′44″ N, 10°01′46″ E. | 5.062222, 10.029444 |
| dest-cmr-005 | [Waza National Park](https://en.wikipedia.org/wiki/Waza_National_Park) | Logone-et-Chari, Far North; 11°20′ N, 14°44′ E is a representative park point, not a gate. | 11.333333, 14.733333 |
| dest-cmr-006 | [Foumban Royal Palace](https://en.wikipedia.org/wiki/Foumban_Royal_Palace) | Palace in Foumban; explicit decimal coordinate. | 5.733044, 10.901154 |
| dest-school-010 | [Lycee General-Leclerc, Yaounde](https://fr.wikipedia.org/wiki/Lyc%C3%A9e_G%C3%A9n%C3%A9ral-Leclerc_(Yaound%C3%A9)) | Ngoa Ekele, Yaounde III; 3°51′21″ N, 11°30′26″ E. Not the school in Saverne, France. | 3.855833, 11.507222 |

### Official institutional evidence without exact pins

| Fetched source | Used for | Verified content and limits |
| --- | --- | --- |
| [Hotel Mont Febe](https://www.hotel-montfebe.cm/) | dest-yao-026, dest-yao-034 | Identifies Hotel Mont Febe in Yaounde, BP 711, and explicitly lists a swimming pool. No exact hotel/pool coordinate adopted. Initial browser extraction failed, but a subsequent HTTP request returned usable content. |
| [AIMT contact](https://aimtinstitute.com/contact) | dest-school-001 | Explicitly lists **Douala Main Campus**, Makepe Carrefour Koppa Cabana, opposite Direction Orange. **Conflicts with the local filename's Yaounde label.** No Yaounde branch or photo identity inferred. |
| [UCAC](https://www.ucac-icy.net/) | dest-school-002 | Contact footer: Nkolbisson, Yaounde, BP 11628. Does not identify which campus is photographed. |
| [ESMATA contact](https://esmata.com/contact/) | dest-school-003 | Full institution name and **Emana pont, Yaounde**. Neighborhood/contact address, not a geolocated entrance. |
| [ICT University](https://ictuniversity.org/) | dest-school-006 | Lists an event at **Yaounde, Zoatupsi Campus**. Event campus association, not a verified current street address or identification of the image's building. |
| [University of Yaounde I faculty page](https://uy1.uninet.cm/faculte-de-medecine-et-des-sciences-biomedicales/) | dest-school-012 | Confirms the Faculty of Medicine and Biomedical Sciences. No faculty entrance coordinate established. |
| [University of Yaounde II](https://site.univ-yaounde2.org/) | dest-school-013 | Official redirected site identifies UY2–SOA and BP 18 Soa, plus BP 1365 Yaounde. Postal contact is not a pin. |

### Contextual, neighborhood and limited evidence

| Fetched source | Used for | What it establishes; what it does not |
| --- | --- | --- |
| [Yaounde](https://en.wikipedia.org/wiki/Yaound%C3%A9) | dest-yao-001 | Capital in Centre Region. A city is not a venue entrance; no city-centroid pin retained. |
| [Bastos](https://fr.wikipedia.org/wiki/Bastos) | dest-yao-008 | Disambiguation entry names Bastos as a Yaounde neighborhood. Does not locate restaurants or gaming venues. |
| [Biyem-Assi](https://fr.wikipedia.org/wiki/Biyem-Assi) | dest-yao-005, 014, 032, 035 | Lists Yaounde VI, Rond-point Express, Marche de Biyem-Assi (acacias), and Hopital de district de Biyem-assi. **Does not verify STORNE or a park**. |
| [Cite Verte](https://fr.wikipedia.org/wiki/Cit%C3%A9_Verte) | dest-yao-010 | Residential neighborhood in Yaounde II. **Does not establish Cite Verte Park**, its facilities, or its entrance. |
| [Sanaga River](https://en.wikipedia.org/wiki/Sanaga_River) | dest-yao-030 | A river spanning East, Centre and Littoral. **Does not identify the supposed Sanaga Lake**, any particular river reach, or the photograph. No river-mouth pin substituted. |
| [Marche Mokolo](https://fr.wikipedia.org/wiki/March%C3%A9_Mokolo) | dest-yao-037 | Market in Mokolo, Yaounde. No exact entrance adopted. |
| [Etoug-Ebe](https://fr.wikipedia.org/wiki/Etoug-Ebe) | dest-school-004 | Yaounde VI neighborhood and named bilingual lycee. No exact school coordinates. |
| [Nkolbisson](https://fr.wikipedia.org/wiki/Nkolbisson) | dest-school-009 | Yaounde VII; separately lists Lycee de Nkolbisson and Lycee Technique de Nkolbisson. Do not conflate them. |
| [Foumban](https://fr.wikipedia.org/wiki/Foumban) | dest-school-011 | City in Noun, West Region. **The technical school's identity remains filename-only**; this citation is city evidence. |
| [University of Yaounde I](https://fr.wikipedia.org/wiki/Universit%C3%A9_de_Yaound%C3%A9_I) | dest-school-012 | Parent university in Ngoa Ekele. Not an exact address of its medical faculty or photographed building. |
| [IUSTY official Facebook page](https://www.facebook.com/IUSTYofficiel/) | dest-school-007 | HTTP fetch exposed only the title **IUSTY - Officiel \| Yaounde**. Limited institution/city evidence, not a campus address. Search snippets mentioning campuses were not promoted to verified locations. |

The Mvog-Betsi Zoo source also informs dest-yao-028's **possible duplicate identity**, not proof of a separate park or a license to copy the zoo's coordinates.

## Identity-preserving corrections

- **dest-yao-009 Memorial Museum:** original ID/name retained, unsupported museum story and pin removed, independence monument photograph detached. The provisional monument has its own dest-yao-036 record, with no assumed city or pin.
- **dest-yao-010 Cite Verte Park:** original ID/name retained, unrelated Biyemassi park photo and unsupported neighborhood-photo fallback detached. New dest-yao-035 holds the Biyemassi filename association, not a verified park address.
- **dest-yao-004 Mount Febe:** hill remains the hill. Hotel photo moved to new dest-yao-034; pool dest-yao-026 retained separately. No summit coordinates assigned to hotel or pool.
- **dest-yao-008 Bastos District:** remains a neighborhood. Restaurant photo moved to new dest-yao-033.
- **dest-yao-029 Lake Ossa:** corrected to Littoral near Dizangue without changing the existing ID, despite its `yao` prefix.
- **dest-yao-030 Sanaga Lake:** unresolved legacy identity retained; no invented lake description, substituted Sanaga River identity, region assertion, image or pin.
- Generic legacy restaurant, arcade, hotel and mosque records remain unverified and unpinned. Their IDs were not recycled for unrelated businesses.

## Complete 57-file inventory

Paths are exact, including spelling, accents and capitalisation. **Linked** means assigned by filename/name, not photo-authenticated. **Provisional** means identity and/or locality still needs independent evidence even if a contextual source exists. **Additional** means another image under an existing destination, not another destination. **Unresolved** means deliberately not assigned anywhere in the dataset.

| # | Asset | Disposition |
| --- | --- | --- |
| 1 | [dining/central markey yaounde.jpg](../frontend/assets/images/dining/central%20markey%20yaounde.jpg) | Additional, dest-yao-022; same Central Market label. |
| 2 | [dining/Kassala restaurant bastos.jpg](../frontend/assets/images/dining/Kassala%20restaurant%20bastos.jpg) | Provisional, dest-yao-017. |
| 3 | [dining/le Continent restaurant bastos.jpg](../frontend/assets/images/dining/le%20Continent%20restaurant%20bastos.jpg) | Provisional, new dest-yao-033; not the district. |
| 4 | [dining/le sims restaurant.jpg](../frontend/assets/images/dining/le%20sims%20restaurant.jpg) | Provisional, dest-yao-018. |
| 5 | [dining/marche biyemassi.jpg](../frontend/assets/images/dining/marche%20biyemassi.jpg) | Linked, dest-yao-005; market/neighborhood source, legacy spelling caveat. |
| 6 | [dining/marche central yaounde.jpg](../frontend/assets/images/dining/marche%20central%20yaounde.jpg) | Provisional, dest-yao-022 primary. |
| 7 | [dining/restaurant biyemassi.jpg](../frontend/assets/images/dining/restaurant%20biyemassi.jpg) | **Unresolved**: neighborhood and venue type, no business name. |
| 8 | [dining/restaurant hybride cameroon.jpg](../frontend/assets/images/dining/restaurant%20hybride%20cameroon.jpg) | Provisional, dest-yao-020; no cuisine inferred. |
| 9 | [dining/restaurant l'heritage bastos.jpg](../frontend/assets/images/dining/restaurant%20l'heritage%20bastos.jpg) | Provisional, dest-yao-021. |
| 10 | [gaming/arcade game bastos.jpg](../frontend/assets/images/gaming/arcade%20game%20bastos.jpg) | **Unresolved**: may depict an activity, not a named business. |
| 11 | [gaming/Game Lounge Essos.jpg](../frontend/assets/images/gaming/Game%20Lounge%20Essos.jpg) | Provisional, dest-yao-011. |
| 12 | [gaming/Isomnia Game Zone.jpg](../frontend/assets/images/gaming/Isomnia%20Game%20Zone.jpg) | Provisional, dest-yao-012; spelling not silently changed. |
| 13 | [gaming/LA FUGA Gaming lounge.jpg](../frontend/assets/images/gaming/LA%20FUGA%20Gaming%20lounge.jpg) | Provisional, dest-yao-013. |
| 14 | [gaming/STORNE Gaming Rond point express.jpg](../frontend/assets/images/gaming/STORNE%20Gaming%20Rond%20point%20express.jpg) | Provisional, dest-yao-014; source confirms locality, not business. |
| 15 | [gaming/VGaming bastos.jpg](../frontend/assets/images/gaming/VGaming%20bastos.jpg) | Provisional, dest-yao-015. |
| 16 | [leisure/hopital biyemassi.jpg](../frontend/assets/images/leisure/hopital%20biyemassi.jpg) | Linked, dest-yao-032; healthcare, not leisure. |
| 17 | [leisure/hotel biyemassi.jpg](../frontend/assets/images/leisure/hotel%20biyemassi.jpg) | **Unresolved**: no hotel business name. |
| 18 | [leisure/hotel mont febe.jpg](../frontend/assets/images/leisure/hotel%20mont%20febe.jpg) | Linked, new dest-yao-034; not hill summit. |
| 19 | [leisure/parc mbiyemassi.jpg](../frontend/assets/images/leisure/parc%20mbiyemassi.jpg) | Provisional, new dest-yao-035; not Cite Verte. |
| 20 | [leisure/parc mvogbetsi.jpg](../frontend/assets/images/leisure/parc%20mvogbetsi.jpg) | Provisional, dest-yao-028; possible zoo duplicate not confirmed. |
| 21 | [leisure/piscine mont febe.jpg](../frontend/assets/images/leisure/piscine%20mont%20febe.jpg) | Linked, dest-yao-026; official site confirms pool, not photo. |
| 22 | [recreational/lake ossa.jpg](../frontend/assets/images/recreational/lake%20ossa.jpg) | Linked, dest-yao-029; corrected to Littoral. |
| 23 | [recreational/mvogbetsi zoo.jpg](../frontend/assets/images/recreational/mvogbetsi%20zoo.jpg) | Linked, dest-yao-007. |
| 24 | [recreational/sanaga lake.jpg](../frontend/assets/images/recreational/sanaga%20lake.jpg) | **Unresolved**: lake, river reach, reservoir or other place not established. |
| 25 | [recreational/waza park.webp](../frontend/assets/images/recreational/waza%20park.webp) | Linked, dest-cmr-005. |
| 26 | [Schools/African Institute of Management and Technology (AIMT), Yaoundé.jpg](../frontend/assets/images/Schools/African%20Institute%20of%20Management%20and%20Technology%20(AIMT),%20Yaoundé.jpg) | Linked by institution name, dest-school-001; **city conflict**, official contact is Douala. |
| 27 | [Schools/Beacon international college.jpg](../frontend/assets/images/Schools/Beacon%20international%20college.jpg) | **Unresolved**: no city; no independently matched local institution. |
| 28 | [Schools/Catholic University of Central Africa (UCAC), Yaoundé.jpg](../frontend/assets/images/Schools/Catholic%20University%20of%20Central%20Africa%20(UCAC),%20Yaoundé.jpg) | Linked, dest-school-002; photographed campus unknown. |
| 29 | [Schools/ESMATA University.jpg](../frontend/assets/images/Schools/ESMATA%20University.jpg) | Linked, dest-school-003; official contact Emana pont. |
| 30 | [Schools/GBHS ETOUG-EBE.jpg](../frontend/assets/images/Schools/GBHS%20ETOUG-EBE.jpg) | Linked, dest-school-004. |
| 31 | [Schools/Global Higher Institute of Management (GHIM), Yaoundé.jpg](../frontend/assets/images/Schools/Global%20Higher%20Institute%20of%20Management%20(GHIM),%20Yaoundé.jpg) | Provisional, dest-school-005; filename-only institution/city. |
| 32 | [Schools/Good Shepherd college.jpg](../frontend/assets/images/Schools/Good%20Shepherd%20college.jpg) | **Unresolved**: common school name, no city or campus. |
| 33 | [Schools/ICT-University.jpg](../frontend/assets/images/Schools/ICT-University.jpg) | Linked, dest-school-006; photographed campus unknown. |
| 34 | [Schools/IUSTY University.jpg](../frontend/assets/images/Schools/IUSTY%20University.jpg) | Linked, dest-school-007; limited name/city evidence, campus unknown. |
| 35 | [Schools/Lycee de l'observatoire.jpg](../frontend/assets/images/Schools/Lycee%20de%20l'observatoire.jpg) | Provisional, dest-school-008; city and address unverified. |
| 36 | [Schools/Lycee De Nkolbisson.jpg](../frontend/assets/images/Schools/Lycee%20De%20Nkolbisson.jpg) | Linked, dest-school-009; not automatically the technical lycee. |
| 37 | [Schools/Lycee General-Leclerc.jpg](../frontend/assets/images/Schools/Lycee%20General-Leclerc.jpg) | Linked, dest-school-010; Yaounde school, not Saverne namesake. |
| 38 | [Schools/Lycee Technique De Foumban.jpg](../frontend/assets/images/Schools/Lycee%20Technique%20De%20Foumban.jpg) | Provisional, dest-school-011; city source confirms West, not campus. |
| 39 | [Schools/New Horizon Academy, Yaoundé.jpg](../frontend/assets/images/Schools/New%20Horizon%20Academy,%20Yaoundé.jpg) | **Unresolved**: city stated, but institution/campus not independently matched. |
| 40 | [Schools/St Mary Bilingual School.jpg](../frontend/assets/images/Schools/St%20Mary%20Bilingual%20School.jpg) | **Unresolved**: common name, no city; do not substitute a namesake. |
| 41 | [Schools/St Stephen International College.jpg](../frontend/assets/images/Schools/St%20Stephen%20International%20College.jpg) | **Unresolved**: institution/city not independently matched. |
| 42 | [Schools/University of Yaoundé I (Faculty of Medicine and Biomedical Sciences).jpg](../frontend/assets/images/Schools/University%20of%20Yaoundé%20I%20(Faculty%20of%20Medicine%20and%20Biomedical%20Sciences).jpg) | Linked, dest-school-012; no parent-university centroid used. |
| 43 | [Schools/University of Yaoundé II.jpg](../frontend/assets/images/Schools/University%20of%20Yaoundé%20II.jpg) | Linked, dest-school-013; official contact Soa, pictured campus unknown. |
| 44 | [shopping/mokolo market.webp](../frontend/assets/images/shopping/mokolo%20market.webp) | Linked, new dest-yao-037. |
| 45 | [shopping/supermarcge dovv bastos.jpg](../frontend/assets/images/shopping/supermarcge%20dovv%20bastos.jpg) | Provisional, dest-yao-025; Bastos branch distinct from other branches. |
| 46 | [shopping/supermarche dovv emana.jpg](../frontend/assets/images/shopping/supermarche%20dovv%20emana.jpg) | Provisional, dest-yao-024. |
| 47 | [shopping/supermarket dovv tongolo.jpg](../frontend/assets/images/shopping/supermarket%20dovv%20tongolo.jpg) | Provisional, dest-yao-023. |
| 48 | [tourist/africa deployments.webp](../frontend/assets/images/tourist/africa%20deployments.webp) | **Unresolved**: no place identity; may not be a destination photograph. |
| 49 | [tourist/basilique marie reine.jpg](../frontend/assets/images/tourist/basilique%20marie%20reine.jpg) | Linked, dest-yao-031. |
| 50 | [tourist/city council.webp](../frontend/assets/images/tourist/city%20council.webp) | **Unresolved**: which council/city/building is unknown. |
| 51 | [tourist/i love my country cameroon monument.webp](../frontend/assets/images/tourist/i%20love%20my%20country%20cameroon%20monument.webp) | **Unresolved**: slogan is not a unique monument/address; not merged into independence/reunification. |
| 52 | [tourist/independence monument.jpg](../frontend/assets/images/tourist/independence%20monument.jpg) | Provisional, new dest-yao-036; specific monument/city unknown, not a museum. |
| 53 | [tourist/museu national.jpg](../frontend/assets/images/tourist/museu%20national.jpg) | Linked, dest-yao-003. |
| 54 | [tourist/parcour vita playground.png](../frontend/assets/images/tourist/parcour%20vita%20playground.png) | Provisional, new dest-yao-038; specific site/city unknown. |
| 55 | [tourist/reunifiacation monument.jpg](../frontend/assets/images/tourist/reunifiacation%20monument.jpg) | Linked, dest-yao-002 primary; local image not authenticated. |
| 56 | [tourist/reunification monument.avif](../frontend/assets/images/tourist/reunification%20monument.avif) | Additional, dest-yao-002; filename variant, subject/city needs visual confirmation. |
| 57 | [tourist/yaounde meseum.jpg](../frontend/assets/images/tourist/yaounde%20meseum.jpg) | **Unresolved**: Yaounde has multiple museums; do not assume National Museum or use as a city photo. |

The 13 bold **Unresolved** inventory rows are the exhaustive list of intentionally unassigned files. Some assigned provisional rows also need identity/location confirmation; unassigned count must not be presented as the total number of uncertain photographs.

## Research limitations and rejected evidence

- Search requests for smaller schools did not yield independently usable institutional pages; later DuckDuckGo requests returned bot challenges. Those failures are not evidence that the schools do not exist. No challenge was bypassed.
- Dovv attempts returned a 404, TLS error or redirect to an unresolvable host; no branch addresses were invented from those results.
- Guessed IUSTY domains failed or led to an unrelated Spanish legal-commerce site. That unrelated site was excluded; only the limited fetched official Facebook title was used.
- The unqualified General-Leclerc Wikipedia page describes **Saverne, France**, and was rejected. The separate Yaounde article was fetched and used.
- Several guessed Wikipedia school/landmark titles returned 404. Existing neighborhood pages were used only for facts actually present, never as evidence that an absent business or facility exists.
- Smaller restaurant/gaming venue records remain filename-only. No reliable exact locations were established, and their previous fabricated-looking Yaounde pins were removed rather than relabeled as verified.
- No OSM/Wikidata coordinates were claimed without a fetched record. Successful Wikipedia pages contain published coordinate evidence; merely linked secondary sources were not treated as fetched sources.

To resolve a provisional or unassigned asset, obtain the photographer's original URL/license, a legible sign or original caption identifying the place, and an authoritative campus/branch address or an unambiguous mapped feature. A city-level geocoder result is insufficient.

## Validation

Read-only PowerShell checks performed against the full edited dataset and image directory:

1. JSON parses; every original ID and name remains unchanged; no duplicate destination IDs.
2. All referenced primary/additional asset strings match actual relative paths **case-sensitively**, including accents, apostrophes, spaces and `Schools`.
3. No asset is assigned to multiple records; 44 assigned plus 13 unassigned accounts for all 57 files. SHA-256 inventory found no byte-identical image files.
4. Every record has address, location notes, URL-string source array and additional-image array. Every cost is null. Every coordinate is a numeric in-range latitude/longitude pair with cited published evidence; all other records omit both fields.
5. Explicit regression checks cover Lake Ossa's Littoral coordinates, Sanaga's missing pin/image, Memorial Museum and Cite Verte retaining their names/IDs without the wrong photos, and distinct hotel/hill/pool and restaurant/district identities.
6. Existing itinerary ID references remain resolvable. One pre-existing itinerary stores the name Reunification Monument instead of an ID; the unchanged name still resolves uniquely. No itinerary was rewritten, and its before/after SHA-256 is unchanged.
7. Documentation inventory matches the file/assignment counts, and the set of dataset source URLs matches the 31-source evidence register.

No Flutter/Python code was modified or executed for this data-only task. JSON/static integrity checks do not constitute a visual app test, image-authenticity audit, current business-status check or guarantee of safe public access.