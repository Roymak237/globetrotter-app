# Destinations waiting on a photograph

These 48 places are **not in the app**. They were removed from `destinations.json` because they had no picture, and parked in `backend/data/destinations_pending_photos.json`. The app currently ships 56 destinations, every one of which has a real image file.

Nine automated searches of freely-licensed repositories (Wikimedia Commons geosearch, Commons text search, Commons category walk, OpenStreetMap picture tags, Openverse, Wikidata P18, Panoramax street-level) found nothing for any of these, so they have to be photographed or sourced by hand.

## How to restore one

1. Drop the photo anywhere under `frontend/assets/images/`. The suggested path below is tidy, but the matcher works on the **name**, so `My Place.webp` sitting at the top level is found just as well.
2. `.jpg`, `.png` and `.webp` all work. Roughly 1200px on the long edge is plenty; the cards never render larger than that.
3. Run `python scripts/restore_destination.py` - it matches files to parked records by name and moves them back into the app.
4. Run `python scripts/verify_destination_images.py` to confirm every shipped destination still resolves to a file that exists.

Note where each photo came from. The app stores an `image_attribution` per destination, and 37 older records already say "creator and license unverified" - a wart worth not repeating.

## The list

### 1. Dolcezza Yde food

- **Save as** `destinations/dolcezza-yde-food.jpg`
- **Record** `dest-yao-040`
- **Kind** restaurant
- **Address** Nouve route bastos, Nkol-Etonn, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.88629, 11.50565](https://www.openstreetmap.org/?mlat=3.886288&mlon=11.505654#map=19/3.886288/11.505654)
- **Coordinate precision** exact

### 2. Bifteck 5 Stars

- **Save as** `destinations/bifteck-5-stars.jpg`
- **Record** `dest-yao-041`
- **Kind** restaurant
- **Address** Rue Jean Abanda, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87381, 11.53917](https://www.openstreetmap.org/?mlat=3.873806&mlon=11.539171#map=19/3.873806/11.539171)
- **Coordinate precision** exact

### 3. Le Premium

- **Save as** `destinations/le-premium.jpg`
- **Record** `dest-yao-042`
- **Kind** restaurant
- **Address** Rue 1.001, Mvogada, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86104, 11.52137](https://www.openstreetmap.org/?mlat=3.861043&mlon=11.521366#map=19/3.861043/11.521366)
- **Coordinate precision** exact

### 4. Jodi Bites

- **Save as** `destinations/jodi-bites.jpg`
- **Record** `dest-yao-043`
- **Kind** restaurant
- **Address** Grand Chefere Simbock, Mbalngong, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.80601, 11.47214](https://www.openstreetmap.org/?mlat=3.806013&mlon=11.472139#map=19/3.806013/11.472139)
- **Coordinate precision** exact

### 5. Le Baron

- **Save as** `destinations/le-baron.jpg`
- **Record** `dest-yao-044`
- **Kind** restaurant
- **Address** Carrefour Bastos, Nkol-Etonn, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.89271, 11.51203](https://www.openstreetmap.org/?mlat=3.892711&mlon=11.512034#map=19/3.892711/11.512034)
- **Coordinate precision** exact

### 6. les merveilles de FOLOLO

- **Save as** `destinations/les-merveilles-de-fololo.jpg`
- **Record** `dest-yao-045`
- **Kind** restaurant
- **Address** Rue 1.570, Tongola-Assi, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.90414, 11.52657](https://www.openstreetmap.org/?mlat=3.90414&mlon=11.52657#map=19/3.90414/11.52657)
- **Coordinate precision** exact

### 7. Le Safoutier

- **Save as** `destinations/le-safoutier.jpg`
- **Record** `dest-yao-046`
- **Kind** restaurant
- **Address** Boulevard du 20 Mai, Mvogada, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86420, 11.51606](https://www.openstreetmap.org/?mlat=3.864197&mlon=11.516061#map=19/3.864197/11.516061)
- **Coordinate precision** exact

### 8. FLORA RESTO

- **Save as** `destinations/flora-resto.jpg`
- **Record** `dest-yao-047`
- **Kind** restaurant
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.83395, 11.49097](https://www.openstreetmap.org/?mlat=3.833949&mlon=11.490974#map=19/3.833949/11.490974)
- **Coordinate precision** exact

### 9. O'GOOD FOOD

- **Save as** `destinations/o-good-food.jpg`
- **Record** `dest-yao-048`
- **Kind** restaurant
- **Address** Odza I, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.80874, 11.52014](https://www.openstreetmap.org/?mlat=3.80874&mlon=11.520139#map=19/3.80874/11.520139)
- **Coordinate precision** exact

### 10. Logiteckcybercafe

- **Save as** `destinations/logiteckcybercafe.jpg`
- **Record** `dest-yao-049`
- **Kind** gaming
- **Address** Avenue de Nsimeyong, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.83215, 11.48961](https://www.openstreetmap.org/?mlat=3.832148&mlon=11.489609#map=19/3.832148/11.489609)
- **Coordinate precision** exact

### 11. Wisad Koncept

- **Save as** `destinations/wisad-koncept.jpg`
- **Record** `dest-yao-050`
- **Kind** gaming
- **Address** Rue 4.804, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86711, 11.56486](https://www.openstreetmap.org/?mlat=3.867114&mlon=11.564865#map=19/3.867114/11.564865)
- **Coordinate precision** exact

### 12. Cyber Et Secrétariat Bureautique

- **Save as** `destinations/cyber-et-secretariat-bureautique.jpg`
- **Record** `dest-yao-051`
- **Kind** gaming
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87762, 11.53258](https://www.openstreetmap.org/?mlat=3.877617&mlon=11.532577#map=19/3.877617/11.532577)
- **Coordinate precision** exact

### 13. Baless Trading Consulting

- **Save as** `destinations/baless-trading-consulting.jpg`
- **Record** `dest-yao-052`
- **Kind** gaming
- **Address** Mvogada, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86171, 11.53009](https://www.openstreetmap.org/?mlat=3.861707&mlon=11.530089#map=19/3.861707/11.530089)
- **Coordinate precision** exact

### 14. Lune Business Center

- **Save as** `destinations/lune-business-center.jpg`
- **Record** `dest-yao-053`
- **Kind** gaming
- **Address** Mvogada, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87115, 11.53447](https://www.openstreetmap.org/?mlat=3.87115&mlon=11.534473#map=19/3.87115/11.534473)
- **Coordinate precision** exact

### 15. Kenza Market 100% Bio

- **Save as** `destinations/kenza-market-100-bio.jpg`
- **Record** `dest-yao-054`
- **Kind** shopping
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.84480, 11.48668](https://www.openstreetmap.org/?mlat=3.844797&mlon=11.486683#map=19/3.844797/11.486683)
- **Coordinate precision** exact

### 16. MIRE WORLD SARL

- **Save as** `destinations/mire-world-sarl.jpg`
- **Record** `dest-yao-055`
- **Kind** shopping
- **Address** Place Elig-Essono, Mvogada, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87239, 11.52416](https://www.openstreetmap.org/?mlat=3.872389&mlon=11.524163#map=19/3.872389/11.524163)
- **Coordinate precision** exact

### 17. Dovv, Tongolo

- **Save as** `destinations/dovv-tongolo.jpg`
- **Record** `dest-yao-056`
- **Kind** shopping
- **Address** Tongola-Assi, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.90814, 11.52877](https://www.openstreetmap.org/?mlat=3.90814&mlon=11.528772#map=19/3.90814/11.528772)
- **Coordinate precision** exact

### 18. Sogali Vitrerie Complexe

- **Save as** `destinations/sogali-vitrerie-complexe.jpg`
- **Record** `dest-yao-057`
- **Kind** shopping
- **Address** Nkolbisson, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87264, 11.45715](https://www.openstreetmap.org/?mlat=3.872641&mlon=11.457151#map=19/3.872641/11.457151)
- **Coordinate precision** exact

### 19. Marché aux Bestiaux

- **Save as** `destinations/marche-aux-bestiaux.jpg`
- **Record** `dest-yao-058`
- **Kind** shopping
- **Address** Zone O, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.88741, 11.49426](https://www.openstreetmap.org/?mlat=3.887413&mlon=11.494258#map=19/3.887413/11.494258)
- **Coordinate precision** exact

### 20. carrefour Kongossa

- **Save as** `destinations/carrefour-kongossa.jpg`
- **Record** `dest-yao-059`
- **Kind** shopping
- **Address** Nkombassi, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.85792, 11.60233](https://www.openstreetmap.org/?mlat=3.857917&mlon=11.602327#map=19/3.857917/11.602327)
- **Coordinate precision** exact

### 21. SANTA LUCIA Melen

- **Save as** `destinations/santa-lucia-melen.jpg`
- **Record** `dest-yao-060`
- **Kind** shopping
- **Address** Zone M, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86409, 11.49536](https://www.openstreetmap.org/?mlat=3.864086&mlon=11.495358#map=19/3.864086/11.495358)
- **Coordinate precision** exact

### 22. Médiathèque de l’Institut français du Cameroun

- **Save as** `destinations/mediatheque-de-linstitut-francais-du-cameroun.jpg`
- **Record** `dest-yao-061`
- **Kind** school
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86779, 11.51158](https://www.openstreetmap.org/?mlat=3.86779&mlon=11.511575#map=19/3.86779/11.511575)
- **Coordinate precision** exact

### 23. Centre de Formation Les Teachers du Web

- **Save as** `destinations/centre-de-formation-les-teachers-du-web.jpg`
- **Record** `dest-yao-062`
- **Kind** school
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.83651, 11.47802](https://www.openstreetmap.org/?mlat=3.836509&mlon=11.47802#map=19/3.836509/11.47802)
- **Coordinate precision** exact

### 24. Institut supérieur de traduction d’interprétation et de communication

- **Save as** `destinations/institut-superieur-de-traduction-dinterpretation-et-de-communication.jpg`
- **Record** `dest-yao-063`
- **Kind** school
- **Address** Zone M, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87035, 11.47937](https://www.openstreetmap.org/?mlat=3.870352&mlon=11.479368#map=19/3.870352/11.479368)
- **Coordinate precision** exact

### 25. Academic School of Excellence

- **Save as** `destinations/academic-school-of-excellence.jpg`
- **Record** `dest-yao-064`
- **Kind** school
- **Address** Rue 1.792, Nkol-Etonn, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.89797, 11.50833](https://www.openstreetmap.org/?mlat=3.897973&mlon=11.508327#map=19/3.897973/11.508327)
- **Coordinate precision** exact

### 26. YSEM

- **Save as** `destinations/ysem.jpg`
- **Record** `dest-yao-065`
- **Kind** school
- **Address** 8.711, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.81518, 11.49292](https://www.openstreetmap.org/?mlat=3.815178&mlon=11.492916#map=19/3.815178/11.492916)
- **Coordinate precision** exact

### 27. Catholic Cross of Ngoya summit

- **Save as** `destinations/catholic-cross-of-ngoya-summit.jpg`
- **Record** `dest-yao-067`
- **Kind** culture
- **Address** Montée du Mt Ngoya, Ngoya III, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.92605, 11.47065](https://www.openstreetmap.org/?mlat=3.926053&mlon=11.470647#map=19/3.926053/11.470647)
- **Coordinate precision** exact

### 28. Village Madiba

- **Save as** `destinations/village-madiba.jpg`
- **Record** `dest-yao-068`
- **Kind** culture
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.94606, 11.56772](https://www.openstreetmap.org/?mlat=3.946063&mlon=11.567722#map=19/3.946063/11.567722)
- **Coordinate precision** exact

### 29. Architec les Concepteurs Réunis, Titi Garage, Yaoundé

- **Save as** `destinations/architec-les-concepteurs-reunis-titi-garage-yaounde.jpg`
- **Record** `dest-yao-069`
- **Kind** culture
- **Address** Mfandéna II, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.88415, 11.55258](https://www.openstreetmap.org/?mlat=3.884152&mlon=11.552578#map=19/3.884152/11.552578)
- **Coordinate precision** exact

### 30. Plus vieux bâtiment en dur de Yaoundé

- **Save as** `destinations/plus-vieux-batiment-en-dur-de-yaounde.jpg`
- **Record** `dest-yao-070`
- **Kind** culture
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86712, 11.51304](https://www.openstreetmap.org/?mlat=3.867118&mlon=11.513035#map=19/3.867118/11.513035)
- **Coordinate precision** exact

### 31. Concrete Mixer, Yaoundé, Ngousso

- **Save as** `destinations/concrete-mixer-yaounde-ngousso.jpg`
- **Record** `dest-yao-071`
- **Kind** culture
- **Address** Tongola-Assi, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.91818, 11.52820](https://www.openstreetmap.org/?mlat=3.918177&mlon=11.528195#map=19/3.918177/11.528195)
- **Coordinate precision** exact

### 32. Résidence GUEFANO MOUDIO

- **Save as** `destinations/residence-guefano-moudio.jpg`
- **Record** `dest-yao-072`
- **Kind** culture
- **Address** Nkolfoulou I, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.91239, 11.56318](https://www.openstreetmap.org/?mlat=3.91239&mlon=11.563179#map=19/3.91239/11.563179)
- **Coordinate precision** exact

### 33. Monastère Notre Dame des Bénédictin du mont Fébé

- **Save as** `destinations/monastere-notre-dame-des-benedictin-du-mont-febe.jpg`
- **Record** `dest-yao-073`
- **Kind** landmark
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.91534, 11.49851](https://www.openstreetmap.org/?mlat=3.915341&mlon=11.498511#map=19/3.915341/11.498511)
- **Coordinate precision** exact

### 34. Salle du Royaume des Témoins de Jéhovah

- **Save as** `destinations/salle-du-royaume-des-temoins-de-jehovah.jpg`
- **Record** `dest-yao-074`
- **Kind** landmark
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.83833, 11.47382](https://www.openstreetmap.org/?mlat=3.838332&mlon=11.47382#map=19/3.838332/11.47382)
- **Coordinate precision** exact

### 35. Saint-Pierre Apôtre de Messamendongo

- **Save as** `destinations/saint-pierre-apotre-de-messamendongo.jpg`
- **Record** `dest-yao-075`
- **Kind** landmark
- **Address** Odza I, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.79528, 11.52050](https://www.openstreetmap.org/?mlat=3.795279&mlon=11.520502#map=19/3.795279/11.520502)
- **Coordinate precision** exact

### 36. Eglise Advantiste du 7e jour

- **Save as** `destinations/eglise-advantiste-du-7e-jour.jpg`
- **Record** `dest-yao-076`
- **Kind** landmark
- **Address** Mfandéna II, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.88814, 11.54381](https://www.openstreetmap.org/?mlat=3.888142&mlon=11.543811#map=19/3.888142/11.543811)
- **Coordinate precision** exact

### 37. Église Presbytérienne Camerounaise Paroisse Margareth Ann-Chasse de Biyem-assi

- **Save as** `destinations/eglise-presbyterienne-camerounaise-paroisse-margareth-ann-chasse-de-biyem-assi.jpg`
- **Record** `dest-yao-077`
- **Kind** landmark
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.83965, 11.48049](https://www.openstreetmap.org/?mlat=3.839653&mlon=11.480489#map=19/3.839653/11.480489)
- **Coordinate precision** exact

### 38. Église Catholique Orthodoxe Byzantine Cathédrale Saint-Michel Archange

- **Save as** `destinations/eglise-catholique-orthodoxe-byzantine-cathedrale-saint-michel-archange.jpg`
- **Record** `dest-yao-078`
- **Kind** landmark
- **Address** Nkolafémé, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.89009, 11.45836](https://www.openstreetmap.org/?mlat=3.890093&mlon=11.45836#map=19/3.890093/11.45836)
- **Coordinate precision** exact

### 39. mballa 2 - stade congo

- **Save as** `destinations/mballa-2-stade-congo.jpg`
- **Record** `dest-yao-079`
- **Kind** leisure, relaxation
- **Address** Rue 1.877, Tongola-Assi, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.90275, 11.51845](https://www.openstreetmap.org/?mlat=3.902748&mlon=11.518455#map=19/3.902748/11.518455)
- **Coordinate precision** exact

### 40. Majestic Yaoundé I University

- **Save as** `destinations/majestic-yaounde-i-university.jpg`
- **Record** `dest-yao-080`
- **Kind** leisure, relaxation
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.85921, 11.49661](https://www.openstreetmap.org/?mlat=3.859211&mlon=11.496607#map=19/3.859211/11.496607)
- **Coordinate precision** exact

### 41. Tennis Club de Yaoundé

- **Save as** `destinations/tennis-club-de-yaounde.jpg`
- **Record** `dest-yao-081`
- **Kind** leisure, relaxation
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87628, 11.51570](https://www.openstreetmap.org/?mlat=3.876276&mlon=11.5157#map=19/3.876276/11.5157)
- **Coordinate precision** exact

### 42. Jardin des amis

- **Save as** `destinations/jardin-des-amis.jpg`
- **Record** `dest-yao-082`
- **Kind** leisure, relaxation
- **Address** Rue Joseph Tchoungui Akoa, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.84740, 11.50197](https://www.openstreetmap.org/?mlat=3.847397&mlon=11.501965#map=19/3.847397/11.501965)
- **Coordinate precision** exact

### 43. reposoire

- **Save as** `destinations/reposoire.jpg`
- **Record** `dest-yao-083`
- **Kind** leisure, relaxation
- **Address** Nkolbisson, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.86411, 11.45995](https://www.openstreetmap.org/?mlat=3.86411&mlon=11.459954#map=19/3.86411/11.459954)
- **Coordinate precision** exact

### 44. Rosy Fitness

- **Save as** `destinations/rosy-fitness.jpg`
- **Record** `dest-yao-084`
- **Kind** sport
- **Address** Montée du Lycée, Zone M, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.87254, 11.48811](https://www.openstreetmap.org/?mlat=3.872542&mlon=11.48811#map=19/3.872542/11.48811)
- **Coordinate precision** exact

### 45. Complexe de La BEAC Centre Sportif et Culturel de NKOL-EKIÉ

- **Save as** `destinations/complexe-de-la-beac-centre-sportif-et-culturel-de-nkol-ekie.jpg`
- **Record** `dest-yao-085`
- **Kind** sport
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.82766, 11.52791](https://www.openstreetmap.org/?mlat=3.827662&mlon=11.527914#map=19/3.827662/11.527914)
- **Coordinate precision** exact

### 46. Centre Technique de la Fédération Camerounaise de Football

- **Save as** `destinations/centre-technique-de-la-federation-camerounaise-de-football.jpg`
- **Record** `dest-yao-086`
- **Kind** sport
- **Address** Odza II, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.78316, 11.53462](https://www.openstreetmap.org/?mlat=3.783158&mlon=11.534619#map=19/3.783158/11.534619)
- **Coordinate precision** exact

### 47. MATECO Complexe Sportif de l'Université de Yaoundé 1

- **Save as** `destinations/mateco-complexe-sportif-de-l-universite-de-yaounde-1.jpg`
- **Record** `dest-yao-087`
- **Kind** sport
- **Address** Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.85753, 11.49723](https://www.openstreetmap.org/?mlat=3.857533&mlon=11.497232#map=19/3.857533/11.497232)
- **Coordinate precision** exact

### 48. Stade de l'église orthodoxe Bastos

- **Save as** `destinations/stade-de-l-eglise-orthodoxe-bastos.jpg`
- **Record** `dest-yao-088`
- **Kind** sport
- **Address** Nkol-Etonn, Yaounde, Centre, Cameroon
- **Location notes** The pin comes from this venue's OpenStreetMap entry, linked below, so it can be checked against the source.
- **Map** [3.89177, 11.51660](https://www.openstreetmap.org/?mlat=3.891773&mlon=11.516602#map=19/3.891773/11.516602)
- **Coordinate precision** exact
