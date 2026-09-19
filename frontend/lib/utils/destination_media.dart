import "../models/destination.dart";

class DestinationMedia {
  final String url;
  final String attribution;

  const DestinationMedia({
    required this.url,
    required this.attribution,
  });
}

/// Verified location-specific fallbacks for records whose local image cannot
/// decode on a target platform. These URLs point to Wikimedia Commons files;
/// each entry keeps the photographer and license visible to the UI.
const verifiedDestinationMedia = <String, DestinationMedia>{
  "dest-yao-001": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/7/75/Yaounde_from_Febe.jpg?width=1200",
    attribution: "Emmanuel Taquet — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-yao-002": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/7/71/Monument_de_la_R%C3%A9unification.JPG?width=1200",
    attribution: "Borigue — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-yao-003": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/1/1d/Mus%C3%A9e_national_de_Yaound%C3%A9_Cameroun.jpg?width=1200",
    attribution: "Manuella sali — Wikimedia Commons, CC BY-SA 4.0",
  ),
  "dest-yao-004": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/7/75/Yaounde_from_Febe.jpg?width=1200",
    attribution: "Emmanuel Taquet — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-yao-007": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/0/00/Mvog-Betsi_Zoo-Botanical_Park.jpg?width=1200",
    attribution: "Eleazar — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-yao-008": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/8/88/Bastos_under_the_moon.jpg?width=1200",
    attribution: "Shaowu Fan — Wikimedia Commons, CC BY 3.0",
  ),
  "dest-yao-010": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/9/97/Cit%C3%A9_Verte07.jpg?width=1200",
    attribution: "Gtankam — Wikimedia Commons, CC BY-SA 4.0",
  ),
  "dest-cmr-001": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/4/4a/Mount_Cameroon.jpg?width=1200",
    attribution: "Daina — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-cmr-002": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/1/19/Limbe_Botanic_Garden.jpg?width=1200",
    attribution: "Awah Nadege — Wikimedia Commons, CC BY-SA 4.0",
  ),
  "dest-cmr-003": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/9/9d/Chutes_de_la_Lob%C3%A9_2.JPG?width=1200",
    attribution: "Aseret Zardep — Wikimedia Commons, CC BY-SA 4.0",
  ),
  "dest-cmr-004": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/8/8c/Ekom_falls.jpg?width=1200",
    attribution: "UJung — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-cmr-005": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/1/10/Waza-NP-Elephant.jpg?width=1200",
    attribution: "Albert Backer — Wikimedia Commons, CC BY-SA 3.0",
  ),
  "dest-cmr-006": DestinationMedia(
    url:
        "https://upload.wikimedia.org/wikipedia/commons/0/0f/The_Sultans_Palace%2C_Foumban.jpg?width=1200",
    attribution: "Elin — Wikimedia Commons, CC BY 2.0",
  ),
};

DestinationMedia? mediaFallbackFor(Destination destination) =>
    verifiedDestinationMedia[destination.id];
