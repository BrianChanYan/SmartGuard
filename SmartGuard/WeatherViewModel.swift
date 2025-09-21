//
//  WeatherViewModel.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import Foundation
import CoreLocation
import Combine

@MainActor
class WeatherViewModel: NSObject, ObservableObject {
    @Published var temperature: String = "--"
    @Published var weatherIcon: String = "questionmark.circle"
    @Published var isLoading = false

    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()

    private var lastLocation: CLLocation?
    private var lastUpdateTime: Date?
    private let cacheValidDuration: TimeInterval = 300 // 5min mem

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers //opt
        requestLocationPermission()
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func fetchWeather() {

        if let lastUpdate = lastUpdateTime,
           let lastLoc = lastLocation,
           Date().timeIntervalSince(lastUpdate) < cacheValidDuration {
            fetchWeatherData(lat: lastLoc.coordinate.latitude, lon: lastLoc.coordinate.longitude)
            return
        }

        if let lastLoc = lastLocation,
           locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            fetchWeatherData(lat: lastLoc.coordinate.latitude, lon: lastLoc.coordinate.longitude)
            return
        }

        isLoading = true
        locationManager.requestLocation()
    }

    private func fetchWeatherData(lat: Double, lon: Double) {
        print("📍 location: lat=\(lat), lon=\(lon)")

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true&timezone=auto"

        print("api URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            self.isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.temperature = "--°C"
                    self?.weatherIcon = "exclamationmark.circle"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP : \(httpResponse.statusCode)")
                }

                if let data = data {

                    // json
                    if let jsonString = String(data: data, encoding: .utf8) {
                    }

                    do {
                        let weather = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                        self?.temperature = "\(Int(weather.current_weather.temperature))°C"
                        self?.updateWeatherIconForCode(weatherCode: weather.current_weather.weathercode)
                        self?.lastUpdateTime = Date()
                    } catch {
                        self?.temperature = "--°C"
                        self?.weatherIcon = "exclamationmark.circle"
                    }
                } else {
                    self?.temperature = "--°C"
                    self?.weatherIcon = "exclamationmark.circle"
                }
            }
        }.resume()
    }

    private func updateWeatherIconForCode(weatherCode: Int) {
        print("weather code: \(weatherCode)")

        // check night or day night: 7pm - 6am
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour >= 19 || hour < 6

        switch weatherCode {
        case 0:
            weatherIcon = isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2:
            weatherIcon = isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3:
            weatherIcon = "cloud.fill"
        case 45, 48:
            weatherIcon = "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            weatherIcon = "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67:
            weatherIcon = isNight ? "cloud.moon.rain.fill" : "cloud.rain.fill"
        case 71, 73, 75, 77:
            weatherIcon = "cloud.snow.fill"
        case 80, 81, 82:
            weatherIcon = "cloud.heavyrain.fill"
        case 85, 86:
            weatherIcon = "cloud.snow.fill"
        case 95, 96, 99:
            weatherIcon = isNight ? "cloud.moon.bolt.fill" : "cloud.bolt.rain.fill"
        default:
            weatherIcon = "questionmark.circle"
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension WeatherViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            return
        }
        lastLocation = location
        fetchWeatherData(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        temperature = "--°C"
        weatherIcon = "exclamationmark.circle"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
    }
}

// MARK: - Open-Meteo Response Models
struct OpenMeteoResponse: Codable {
    let current_weather: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature: Double
    let windspeed: Double
    let winddirection: Double
    let weathercode: Int
    let time: String
}
