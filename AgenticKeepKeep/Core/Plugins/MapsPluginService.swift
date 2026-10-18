import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class MapsPluginService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MapsPluginService()
    struct Place: Identifiable { var id: String; var name: String; var address: String; var coordinate: CLLocationCoordinate2D }
    @Published private(set) var places: [Place] = []
    private var cachedPlaces: [String: Place] = [:]
    @Published private(set) var locationStatus = "未使用定位"
    private let locationManager = CLLocationManager()
    private var locationWaiter: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var locationTimeout: Task<Void, Never>?
    private var searchTask: MKLocalSearch?
    private var generation = UUID()
    override init() { super.init(); locationManager.delegate = self }
    func reset() {
        generation = UUID(); searchTask?.cancel(); searchTask = nil; places = []; cachedPlaces = [:]
        finishLocation(.failure(CancellationError()))
    }
    func authorize() { locationManager.requestWhenInUseAuthorization() }
    var authorizationStatus: CLAuthorizationStatus { locationManager.authorizationStatus }
    /// Await the decision, without starting location acquisition.
    func authorizeForConnection() async throws {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        try Task.checkCancellation()
        locationManager.requestWhenInUseAuthorization()
        while locationManager.authorizationStatus == .notDetermined {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) ? "可使用当前位置" : "未授权当前位置，可手填地点"
    }
    private func currentLocation() async throws -> CLLocationCoordinate2D {
        guard [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) else {
            throw CoachPluginError.unavailable("附近查询需要使用期间定位，请在插件设置中授权，或直接提供起点/地点名称。")
        }
        guard locationWaiter == nil else { throw CoachPluginError.unavailable("正在获取位置，请稍后。") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationWaiter = continuation; locationManager.requestLocation()
                locationTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled else { return }
                    self?.finishLocation(.failure(CoachPluginError.unavailable("获取位置超时，请提供地点名称。")))
                }
            }
        } onCancel: { Task { @MainActor in self.finishLocation(.failure(CancellationError())) } }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0, abs(value.timestamp.timeIntervalSinceNow) < 60 else { return }
        finishLocation(.success(value.coordinate))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finishLocation(.failure(error)) }
    private func finishLocation(_ result: Result<CLLocationCoordinate2D, Error>) {
        locationTimeout?.cancel(); locationTimeout = nil; locationManager.stopUpdatingLocation()
        let waiter = locationWaiter; locationWaiter = nil; waiter?.resume(with: result)
    }
    func search(_ text: String, nearby: Bool, revalidate: () throws -> Void) async throws -> [Place] {
        guard !text.isEmpty, text.count <= 200 else { throw CoachPluginError.invalid }
        let marker = generation
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
        if nearby { request.region = MKCoordinateRegion(center: try await currentLocation(), latitudinalMeters: 8000, longitudinalMeters: 8000) }
        try revalidate(); try Task.checkCancellation()
        let search = MKLocalSearch(request: request); searchTask = search
        let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
        try revalidate(); try Task.checkCancellation()
        guard generation == marker else { throw CoachPluginError.accountChanged }
        places = response.mapItems.prefix(10).map { Place(id: UUID().uuidString, name: $0.name ?? "地点", address: $0.placemark.title ?? "", coordinate: $0.placemark.coordinate) }
        if cachedPlaces.count > 200 { cachedPlaces = [:] }
        for place in places { cachedPlaces[place.id] = place }
        searchTask = nil
        return places
    }
    func place(_ token: String) throws -> Place {
        guard let place = cachedPlaces[token] else { throw CoachPluginError.stale }; return place
    }
    func open(latitude: Double, longitude: Double, title: String, transport: String, originLatitude: Double? = nil, originLongitude: Double? = nil, originTitle: String? = nil) async throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw CoachPluginError.invalid }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = title
        let mode: String
        switch transport {
        case "walking": mode = MKLaunchOptionsDirectionsModeWalking
        case "driving": mode = MKLaunchOptionsDirectionsModeDriving
        case "transit": mode = MKLaunchOptionsDirectionsModeTransit
        case "cycling": mode = MKLaunchOptionsDirectionsModeCycling
        default: throw CoachPluginError.invalid
        }
        let opened: Bool
        if let a = originLatitude, let b = originLongitude {
            guard a.isFinite, b.isFinite, (-90...90).contains(a), (-180...180).contains(b) else { throw CoachPluginError.invalid }
            let origin = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: a, longitude: b)))
            origin.name = originTitle
            opened = await MKMapItem.openMaps(with: [origin, item], launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
        } else {
            guard originLatitude == nil, originLongitude == nil else { throw CoachPluginError.invalid }
            opened = await item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
        }
        guard opened else { throw CoachPluginError.unavailable("未能打开 Apple 地图，请重试。") }
    }
}
