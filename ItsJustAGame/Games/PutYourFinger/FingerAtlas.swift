import Foundation

struct FingerPlace: Hashable {
    let name: String
    let capital: String
    let coordinate: Coordinate
}

struct FingerRegion {
    let name: String
    let center: Coordinate
    let spanLat: Double
    let spanLon: Double
    let places: [FingerPlace]
}

/// The question bank: regions shown as bare (satellite) maps, each with
/// places whose capital is the scoring target. Coordinates are approximate
/// capital locations — every player is scored against the same target, so
/// small inaccuracies never affect fairness.
enum FingerAtlas {
    private static func p(_ name: String, _ capital: String, _ lat: Double, _ lon: Double) -> FingerPlace {
        FingerPlace(name: name, capital: capital, coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    static let regions: [FingerRegion] = [europe, africa, asia, southAmerica, usStates]

    static let europe = FingerRegion(
        name: "Europe",
        center: Coordinate(latitude: 53, longitude: 12),
        spanLat: 30,
        spanLon: 44,
        places: [
            p("Albania", "Tirana", 41.33, 19.82),
            p("Austria", "Vienna", 48.21, 16.37),
            p("Belgium", "Brussels", 50.85, 4.35),
            p("Bulgaria", "Sofia", 42.70, 23.32),
            p("Croatia", "Zagreb", 45.81, 15.98),
            p("Czechia", "Prague", 50.09, 14.42),
            p("Denmark", "Copenhagen", 55.68, 12.57),
            p("Estonia", "Tallinn", 59.44, 24.75),
            p("Finland", "Helsinki", 60.17, 24.94),
            p("France", "Paris", 48.86, 2.35),
            p("Germany", "Berlin", 52.52, 13.40),
            p("Greece", "Athens", 37.98, 23.73),
            p("Hungary", "Budapest", 47.50, 19.04),
            p("Iceland", "Reykjavik", 64.15, -21.94),
            p("Ireland", "Dublin", 53.35, -6.26),
            p("Italy", "Rome", 41.90, 12.50),
            p("Latvia", "Riga", 56.95, 24.11),
            p("Lithuania", "Vilnius", 54.69, 25.28),
            p("Netherlands", "Amsterdam", 52.37, 4.90),
            p("Norway", "Oslo", 59.91, 10.75),
            p("Poland", "Warsaw", 52.23, 21.01),
            p("Portugal", "Lisbon", 38.72, -9.14),
            p("Romania", "Bucharest", 44.43, 26.10),
            p("Serbia", "Belgrade", 44.79, 20.45),
            p("Slovakia", "Bratislava", 48.15, 17.11),
            p("Slovenia", "Ljubljana", 46.06, 14.51),
            p("Spain", "Madrid", 40.42, -3.70),
            p("Sweden", "Stockholm", 59.33, 18.07),
            p("Switzerland", "Bern", 46.95, 7.45),
            p("Ukraine", "Kyiv", 50.45, 30.52),
            p("United Kingdom", "London", 51.51, -0.13),
        ]
    )

    static let africa = FingerRegion(
        name: "Africa",
        center: Coordinate(latitude: 1, longitude: 17),
        spanLat: 74,
        spanLon: 66,
        places: [
            p("Algeria", "Algiers", 36.75, 3.06),
            p("Angola", "Luanda", -8.84, 13.23),
            p("Botswana", "Gaborone", -24.63, 25.92),
            p("Cameroon", "Yaoundé", 3.87, 11.52),
            p("Chad", "N'Djamena", 12.13, 15.06),
            p("DR Congo", "Kinshasa", -4.44, 15.27),
            p("Egypt", "Cairo", 30.04, 31.24),
            p("Ethiopia", "Addis Ababa", 9.03, 38.74),
            p("Ghana", "Accra", 5.60, -0.19),
            p("Ivory Coast", "Yamoussoukro", 6.83, -5.29),
            p("Kenya", "Nairobi", -1.29, 36.82),
            p("Libya", "Tripoli", 32.89, 13.19),
            p("Madagascar", "Antananarivo", -18.88, 47.51),
            p("Mali", "Bamako", 12.64, -8.00),
            p("Morocco", "Rabat", 34.02, -6.84),
            p("Mozambique", "Maputo", -25.97, 32.57),
            p("Namibia", "Windhoek", -22.56, 17.08),
            p("Niger", "Niamey", 13.51, 2.13),
            p("Nigeria", "Abuja", 9.06, 7.50),
            p("Senegal", "Dakar", 14.72, -17.47),
            p("Somalia", "Mogadishu", 2.05, 45.32),
            p("South Africa", "Pretoria", -25.75, 28.19),
            p("Sudan", "Khartoum", 15.50, 32.56),
            p("Tanzania", "Dodoma", -6.16, 35.75),
            p("Tunisia", "Tunis", 36.81, 10.18),
            p("Uganda", "Kampala", 0.35, 32.58),
            p("Zambia", "Lusaka", -15.39, 28.32),
            p("Zimbabwe", "Harare", -17.83, 31.05),
        ]
    )

    static let asia = FingerRegion(
        name: "Asia",
        center: Coordinate(latitude: 28, longitude: 90),
        spanLat: 58,
        spanLon: 105,
        places: [
            p("Afghanistan", "Kabul", 34.53, 69.17),
            p("Bangladesh", "Dhaka", 23.81, 90.41),
            p("Cambodia", "Phnom Penh", 11.56, 104.92),
            p("China", "Beijing", 39.90, 116.41),
            p("India", "New Delhi", 28.61, 77.21),
            p("Indonesia", "Jakarta", -6.21, 106.85),
            p("Iran", "Tehran", 35.69, 51.39),
            p("Iraq", "Baghdad", 33.31, 44.36),
            p("Japan", "Tokyo", 35.68, 139.69),
            p("Jordan", "Amman", 31.95, 35.93),
            p("Kazakhstan", "Astana", 51.17, 71.45),
            p("Malaysia", "Kuala Lumpur", 3.14, 101.69),
            p("Mongolia", "Ulaanbaatar", 47.89, 106.91),
            p("Myanmar", "Naypyidaw", 19.76, 96.08),
            p("Nepal", "Kathmandu", 27.72, 85.32),
            p("North Korea", "Pyongyang", 39.04, 125.76),
            p("Pakistan", "Islamabad", 33.68, 73.05),
            p("Philippines", "Manila", 14.60, 120.98),
            p("Saudi Arabia", "Riyadh", 24.71, 46.68),
            p("South Korea", "Seoul", 37.57, 126.98),
            p("Sri Lanka", "Colombo", 6.93, 79.86),
            p("Thailand", "Bangkok", 13.76, 100.50),
            p("Turkey", "Ankara", 39.93, 32.86),
            p("United Arab Emirates", "Abu Dhabi", 24.45, 54.38),
            p("Uzbekistan", "Tashkent", 41.30, 69.24),
            p("Vietnam", "Hanoi", 21.03, 105.85),
        ]
    )

    static let southAmerica = FingerRegion(
        name: "South America",
        center: Coordinate(latitude: -16, longitude: -60),
        spanLat: 60,
        spanLon: 48,
        places: [
            p("Argentina", "Buenos Aires", -34.60, -58.38),
            p("Bolivia", "La Paz", -16.49, -68.15),
            p("Brazil", "Brasília", -15.79, -47.88),
            p("Chile", "Santiago", -33.45, -70.67),
            p("Colombia", "Bogotá", 4.71, -74.07),
            p("Ecuador", "Quito", -0.18, -78.47),
            p("Guyana", "Georgetown", 6.80, -58.16),
            p("Paraguay", "Asunción", -25.26, -57.58),
            p("Peru", "Lima", -12.05, -77.04),
            p("Suriname", "Paramaribo", 5.85, -55.20),
            p("Uruguay", "Montevideo", -34.90, -56.16),
            p("Venezuela", "Caracas", 10.48, -66.90),
        ]
    )

    /// North America plays as US states — the target is the state capital.
    static let usStates = FingerRegion(
        name: "United States",
        center: Coordinate(latitude: 39.5, longitude: -98.35),
        spanLat: 28,
        spanLon: 62,
        places: [
            p("Alabama", "Montgomery", 32.38, -86.30),
            p("Arizona", "Phoenix", 33.45, -112.07),
            p("Arkansas", "Little Rock", 34.75, -92.29),
            p("California", "Sacramento", 38.58, -121.49),
            p("Colorado", "Denver", 39.74, -104.99),
            p("Connecticut", "Hartford", 41.76, -72.68),
            p("Delaware", "Dover", 39.16, -75.52),
            p("Florida", "Tallahassee", 30.44, -84.28),
            p("Georgia", "Atlanta", 33.75, -84.39),
            p("Idaho", "Boise", 43.62, -116.20),
            p("Illinois", "Springfield", 39.80, -89.65),
            p("Indiana", "Indianapolis", 39.77, -86.16),
            p("Iowa", "Des Moines", 41.59, -93.60),
            p("Kansas", "Topeka", 39.05, -95.68),
            p("Kentucky", "Frankfort", 38.19, -84.87),
            p("Louisiana", "Baton Rouge", 30.45, -91.19),
            p("Maine", "Augusta", 44.31, -69.78),
            p("Maryland", "Annapolis", 38.98, -76.49),
            p("Massachusetts", "Boston", 42.36, -71.06),
            p("Michigan", "Lansing", 42.73, -84.55),
            p("Minnesota", "St. Paul", 44.95, -93.09),
            p("Mississippi", "Jackson", 32.30, -90.18),
            p("Missouri", "Jefferson City", 38.58, -92.17),
            p("Montana", "Helena", 46.59, -112.04),
            p("Nebraska", "Lincoln", 40.81, -96.70),
            p("Nevada", "Carson City", 39.16, -119.77),
            p("New Hampshire", "Concord", 43.21, -71.54),
            p("New Jersey", "Trenton", 40.22, -74.76),
            p("New Mexico", "Santa Fe", 35.69, -105.94),
            p("New York", "Albany", 42.65, -73.75),
            p("North Carolina", "Raleigh", 35.78, -78.64),
            p("North Dakota", "Bismarck", 46.81, -100.78),
            p("Ohio", "Columbus", 39.96, -83.00),
            p("Oklahoma", "Oklahoma City", 35.47, -97.52),
            p("Oregon", "Salem", 44.94, -123.03),
            p("Pennsylvania", "Harrisburg", 40.26, -76.88),
            p("Rhode Island", "Providence", 41.82, -71.41),
            p("South Carolina", "Columbia", 34.00, -81.03),
            p("South Dakota", "Pierre", 44.37, -100.35),
            p("Tennessee", "Nashville", 36.16, -86.78),
            p("Texas", "Austin", 30.27, -97.74),
            p("Utah", "Salt Lake City", 40.76, -111.89),
            p("Vermont", "Montpelier", 44.26, -72.58),
            p("Virginia", "Richmond", 37.54, -77.44),
            p("Washington", "Olympia", 47.04, -122.90),
            p("West Virginia", "Charleston", 38.35, -81.63),
            p("Wisconsin", "Madison", 43.07, -89.40),
            p("Wyoming", "Cheyenne", 41.14, -104.82),
        ]
    )
}
