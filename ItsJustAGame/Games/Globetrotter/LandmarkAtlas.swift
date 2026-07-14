import Foundation

struct Landmark: Hashable {
    let name: String
    let country: String
    let continent: String
    let coordinate: Coordinate
}

/// Globetrotter's question bank: famous landmarks shown as a name against a
/// bare world map, the coordinate hidden until the reveal. Locations are
/// approximate (city-level) — every player is scored against the same
/// target, so small inaccuracies never affect fairness, and at world scale
/// they're invisible anyway.
enum LandmarkAtlas {
    private static func l(_ name: String, _ country: String, _ continent: String, _ lat: Double, _ lon: Double) -> Landmark {
        Landmark(name: name, country: country, continent: continent, coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    static let all: [Landmark] = europe + asia + northAmerica + southAmerica + africa + oceania

    // MARK: Europe
    static let europe: [Landmark] = [
        l("Eiffel Tower", "France", "Europe", 48.8584, 2.2945),
        l("Louvre Museum", "France", "Europe", 48.8606, 2.3376),
        l("Arc de Triomphe", "France", "Europe", 48.8738, 2.2950),
        l("Notre-Dame Cathedral", "France", "Europe", 48.8530, 2.3499),
        l("Sacré-Cœur", "France", "Europe", 48.8867, 2.3431),
        l("Palace of Versailles", "France", "Europe", 48.8049, 2.1204),
        l("Mont Saint-Michel", "France", "Europe", 48.6361, -1.5115),
        l("Colosseum", "Italy", "Europe", 41.8902, 12.4922),
        l("Leaning Tower of Pisa", "Italy", "Europe", 43.7230, 10.3966),
        l("St. Peter's Basilica", "Vatican City", "Europe", 41.9022, 12.4539),
        l("Trevi Fountain", "Italy", "Europe", 41.9009, 12.4833),
        l("St. Mark's Square", "Italy", "Europe", 45.4342, 12.3388),
        l("Milan Cathedral", "Italy", "Europe", 45.4642, 9.1900),
        l("Florence Cathedral", "Italy", "Europe", 43.7731, 11.2560),
        l("Pompeii", "Italy", "Europe", 40.7497, 14.4869),
        l("Cinque Terre", "Italy", "Europe", 44.1461, 9.6439),
        l("Sagrada Família", "Spain", "Europe", 41.4036, 2.1744),
        l("Alhambra", "Spain", "Europe", 37.1761, -3.5881),
        l("Guggenheim Bilbao", "Spain", "Europe", 43.2687, -2.9340),
        l("Aqueduct of Segovia", "Spain", "Europe", 40.9481, -4.1184),
        l("Big Ben", "United Kingdom", "Europe", 51.5007, -0.1246),
        l("Tower Bridge", "United Kingdom", "Europe", 51.5055, -0.0754),
        l("Buckingham Palace", "United Kingdom", "Europe", 51.5014, -0.1419),
        l("London Eye", "United Kingdom", "Europe", 51.5033, -0.1195),
        l("Stonehenge", "United Kingdom", "Europe", 51.1789, -1.8262),
        l("Edinburgh Castle", "United Kingdom", "Europe", 55.9486, -3.1999),
        l("Giant's Causeway", "United Kingdom", "Europe", 55.2408, -6.5116),
        l("Brandenburg Gate", "Germany", "Europe", 52.5163, 13.3777),
        l("Neuschwanstein Castle", "Germany", "Europe", 47.5576, 10.7498),
        l("Cologne Cathedral", "Germany", "Europe", 50.9413, 6.9583),
        l("Acropolis of Athens", "Greece", "Europe", 37.9715, 23.7267),
        l("Santorini", "Greece", "Europe", 36.4618, 25.3753),
        l("Meteora", "Greece", "Europe", 39.7217, 21.6306),
        l("Amsterdam Canals", "Netherlands", "Europe", 52.3676, 4.9041),
        l("Nyhavn", "Denmark", "Europe", 55.6805, 12.5915),
        l("Charles Bridge", "Czechia", "Europe", 50.0865, 14.4114),
        l("Prague Castle", "Czechia", "Europe", 50.0911, 14.4016),
        l("Matterhorn", "Switzerland", "Europe", 45.9763, 7.6586),
        l("Atomium", "Belgium", "Europe", 50.8949, 4.3415),
        l("Geirangerfjord", "Norway", "Europe", 62.1010, 7.0060),
        l("Blue Lagoon", "Iceland", "Europe", 63.8804, -22.4495),
        l("Red Square", "Russia", "Europe", 55.7539, 37.6208),
        l("Saint Basil's Cathedral", "Russia", "Europe", 55.7525, 37.6231),
        l("Hermitage Museum", "Russia", "Europe", 59.9398, 30.3146),
        l("Cliffs of Moher", "Ireland", "Europe", 52.9715, -9.4309),
        l("Belém Tower", "Portugal", "Europe", 38.6916, -9.2160),
        l("Pena Palace", "Portugal", "Europe", 38.7876, -9.3906),
        l("Hungarian Parliament", "Hungary", "Europe", 47.5072, 19.0455),
        l("Bran Castle", "Romania", "Europe", 45.5149, 25.3671),
        l("Dubrovnik Old Town", "Croatia", "Europe", 42.6407, 18.1077),
        l("Plitvice Lakes", "Croatia", "Europe", 44.8654, 15.5820),
        l("Hallstatt", "Austria", "Europe", 47.5622, 13.6493),
        l("Schönbrunn Palace", "Austria", "Europe", 48.1858, 16.3122),
        l("Lake Bled", "Slovenia", "Europe", 46.3625, 14.0928),
        l("Kraków Old Town", "Poland", "Europe", 50.0616, 19.9373),
    ]

    // MARK: Asia
    static let asia: [Landmark] = [
        l("Taj Mahal", "India", "Asia", 27.1751, 78.0421),
        l("Gateway of India", "India", "Asia", 18.9220, 72.8347),
        l("Golden Temple", "India", "Asia", 31.6200, 74.8765),
        l("Hawa Mahal", "India", "Asia", 26.9239, 75.8267),
        l("Lotus Temple", "India", "Asia", 28.5535, 77.2588),
        l("Amber Fort", "India", "Asia", 26.9855, 75.8513),
        l("Great Wall of China", "China", "Asia", 40.4319, 116.5704),
        l("Forbidden City", "China", "Asia", 39.9163, 116.3972),
        l("Terracotta Army", "China", "Asia", 34.3841, 109.2785),
        l("The Bund", "China", "Asia", 31.2397, 121.4900),
        l("Potala Palace", "China", "Asia", 29.6570, 91.1170),
        l("Victoria Harbour", "Hong Kong", "Asia", 22.2793, 114.1628),
        l("Mount Everest", "Nepal", "Asia", 27.9881, 86.9250),
        l("Mount Fuji", "Japan", "Asia", 35.3606, 138.7274),
        l("Tokyo Tower", "Japan", "Asia", 35.6586, 139.7454),
        l("Sensō-ji", "Japan", "Asia", 35.7148, 139.7967),
        l("Fushimi Inari Shrine", "Japan", "Asia", 34.9671, 135.7727),
        l("Kinkaku-ji", "Japan", "Asia", 35.0394, 135.7292),
        l("Petronas Towers", "Malaysia", "Asia", 3.1579, 101.7116),
        l("Marina Bay Sands", "Singapore", "Asia", 1.2834, 103.8607),
        l("Grand Palace", "Thailand", "Asia", 13.7500, 100.4913),
        l("Wat Arun", "Thailand", "Asia", 13.7437, 100.4889),
        l("Angkor Wat", "Cambodia", "Asia", 13.4125, 103.8670),
        l("Ha Long Bay", "Vietnam", "Asia", 20.9101, 107.1839),
        l("Borobudur", "Indonesia", "Asia", -7.6079, 110.2038),
        l("Tanah Lot", "Indonesia", "Asia", -8.6212, 115.0868),
        l("Petra", "Jordan", "Asia", 30.3285, 35.4444),
        l("Burj Khalifa", "United Arab Emirates", "Asia", 25.1972, 55.2744),
        l("Sheikh Zayed Grand Mosque", "United Arab Emirates", "Asia", 24.4128, 54.4750),
        l("Hagia Sophia", "Turkey", "Asia", 41.0086, 28.9800),
        l("Blue Mosque", "Turkey", "Asia", 41.0054, 28.9768),
        l("Cappadocia", "Turkey", "Asia", 38.6431, 34.8289),
        l("Persepolis", "Iran", "Asia", 29.9354, 52.8916),
        l("Registan", "Uzbekistan", "Asia", 39.6547, 66.9758),
        l("Western Wall", "Israel", "Asia", 31.7767, 35.2345),
        l("Gyeongbokgung Palace", "South Korea", "Asia", 37.5796, 126.9770),
        l("N Seoul Tower", "South Korea", "Asia", 37.5512, 126.9882),
        l("Shwedagon Pagoda", "Myanmar", "Asia", 16.7983, 96.1497),
        l("Sigiriya", "Sri Lanka", "Asia", 7.9570, 80.7603),
        l("Chocolate Hills", "Philippines", "Asia", 9.8290, 124.1430),
        l("Banaue Rice Terraces", "Philippines", "Asia", 16.9289, 121.0570),
        l("Jeju Island", "South Korea", "Asia", 33.3617, 126.5292),
    ]

    // MARK: North America
    static let northAmerica: [Landmark] = [
        l("Statue of Liberty", "USA", "North America", 40.6892, -74.0445),
        l("Empire State Building", "USA", "North America", 40.7484, -73.9857),
        l("Times Square", "USA", "North America", 40.7580, -73.9855),
        l("Brooklyn Bridge", "USA", "North America", 40.7061, -73.9969),
        l("Central Park", "USA", "North America", 40.7829, -73.9654),
        l("Golden Gate Bridge", "USA", "North America", 37.8199, -122.4783),
        l("Alcatraz Island", "USA", "North America", 37.8267, -122.4230),
        l("Hollywood Sign", "USA", "North America", 34.1341, -118.3215),
        l("Grand Canyon", "USA", "North America", 36.1069, -112.1129),
        l("Mount Rushmore", "USA", "North America", 43.8791, -103.4591),
        l("White House", "USA", "North America", 38.8977, -77.0365),
        l("Washington Monument", "USA", "North America", 38.8895, -77.0353),
        l("Lincoln Memorial", "USA", "North America", 38.8893, -77.0502),
        l("US Capitol", "USA", "North America", 38.8899, -77.0091),
        l("Las Vegas Strip", "USA", "North America", 36.1147, -115.1728),
        l("Niagara Falls", "USA", "North America", 43.0962, -79.0377),
        l("Old Faithful", "USA", "North America", 44.4605, -110.8281),
        l("Space Needle", "USA", "North America", 47.6205, -122.3493),
        l("Gateway Arch", "USA", "North America", 38.6247, -90.1848),
        l("Monument Valley", "USA", "North America", 36.9980, -110.0985),
        l("Antelope Canyon", "USA", "North America", 36.8619, -111.3743),
        l("Yosemite Valley", "USA", "North America", 37.7459, -119.5332),
        l("Walt Disney World", "USA", "North America", 28.3852, -81.5639),
        l("Willis Tower", "USA", "North America", 41.8789, -87.6359),
        l("CN Tower", "Canada", "North America", 43.6426, -79.3871),
        l("Lake Louise", "Canada", "North America", 51.4254, -116.1773),
        l("Château Frontenac", "Canada", "North America", 46.8118, -71.2048),
        l("Parliament Hill", "Canada", "North America", 45.4236, -75.7009),
        l("Chichén Itzá", "Mexico", "North America", 20.6843, -88.5678),
        l("Teotihuacán", "Mexico", "North America", 19.6925, -98.8438),
        l("Panama Canal", "Panama", "North America", 9.0800, -79.6800),
        l("Tikal", "Guatemala", "North America", 17.2220, -89.6237),
    ]

    // MARK: South America
    static let southAmerica: [Landmark] = [
        l("Christ the Redeemer", "Brazil", "South America", -22.9519, -43.2105),
        l("Sugarloaf Mountain", "Brazil", "South America", -22.9492, -43.1545),
        l("Copacabana Beach", "Brazil", "South America", -22.9711, -43.1822),
        l("Iguazú Falls", "Brazil", "South America", -25.6953, -54.4367),
        l("Amazon Rainforest", "Brazil", "South America", -3.4653, -62.2159),
        l("Machu Picchu", "Peru", "South America", -13.1631, -72.5450),
        l("Nazca Lines", "Peru", "South America", -14.7390, -75.1300),
        l("Rainbow Mountain", "Peru", "South America", -13.8712, -71.3020),
        l("Lake Titicaca", "Peru", "South America", -15.9254, -69.3354),
        l("Salar de Uyuni", "Bolivia", "South America", -20.1338, -67.4891),
        l("Perito Moreno Glacier", "Argentina", "South America", -50.4967, -73.1377),
        l("Torres del Paine", "Chile", "South America", -50.9423, -73.4068),
        l("Easter Island", "Chile", "South America", -27.1212, -109.3667),
        l("Atacama Desert", "Chile", "South America", -24.5000, -69.2500),
        l("Galápagos Islands", "Ecuador", "South America", -0.9538, -90.9656),
        l("Cotopaxi", "Ecuador", "South America", -0.6807, -78.4377),
        l("Angel Falls", "Venezuela", "South America", 5.9701, -62.5362),
        l("Cartagena Old Town", "Colombia", "South America", 10.4236, -75.5513),
    ]

    // MARK: Africa
    static let africa: [Landmark] = [
        l("Great Pyramid of Giza", "Egypt", "Africa", 29.9792, 31.1342),
        l("Valley of the Kings", "Egypt", "Africa", 25.7402, 32.6014),
        l("Abu Simbel", "Egypt", "Africa", 22.3372, 31.6258),
        l("Table Mountain", "South Africa", "Africa", -33.9628, 18.4098),
        l("Cape of Good Hope", "South Africa", "Africa", -34.3568, 18.4740),
        l("Robben Island", "South Africa", "Africa", -33.8076, 18.3712),
        l("Victoria Falls", "Zambia", "Africa", -17.9243, 25.8572),
        l("Mount Kilimanjaro", "Tanzania", "Africa", -3.0674, 37.3556),
        l("Serengeti", "Tanzania", "Africa", -2.3333, 34.8333),
        l("Stone Town, Zanzibar", "Tanzania", "Africa", -6.1629, 39.1892),
        l("Jemaa el-Fnaa", "Morocco", "Africa", 31.6258, -7.9891),
        l("Hassan II Mosque", "Morocco", "Africa", 33.6083, -7.6325),
        l("Chefchaouen", "Morocco", "Africa", 35.1688, -5.2636),
        l("Sahara Desert", "Morocco", "Africa", 31.1000, -4.0000),
        l("Maasai Mara", "Kenya", "Africa", -1.4931, 35.1439),
        l("Great Mosque of Djenné", "Mali", "Africa", 13.9053, -4.5551),
        l("Sossusvlei", "Namibia", "Africa", -24.7333, 15.3500),
        l("Okavango Delta", "Botswana", "Africa", -19.2800, 22.8100),
    ]

    // MARK: Oceania
    static let oceania: [Landmark] = [
        l("Sydney Opera House", "Australia", "Oceania", -33.8568, 151.2153),
        l("Sydney Harbour Bridge", "Australia", "Oceania", -33.8523, 151.2108),
        l("Uluru", "Australia", "Oceania", -25.3444, 131.0369),
        l("Great Barrier Reef", "Australia", "Oceania", -18.2871, 147.6992),
        l("Twelve Apostles", "Australia", "Oceania", -38.6662, 143.1044),
        l("Bondi Beach", "Australia", "Oceania", -33.8908, 151.2743),
        l("Whitsunday Islands", "Australia", "Oceania", -20.2840, 148.9000),
        l("Milford Sound", "New Zealand", "Oceania", -44.6414, 167.8974),
        l("Hobbiton", "New Zealand", "Oceania", -37.8721, 175.6829),
        l("Sky Tower", "New Zealand", "Oceania", -36.8485, 174.7621),
        l("Aoraki / Mount Cook", "New Zealand", "Oceania", -43.5950, 170.1418),
        l("Bora Bora", "French Polynesia", "Oceania", -16.5004, -151.7415),
    ]
}
