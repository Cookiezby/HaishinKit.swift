struct Preference {
    static var defaultInstance = Preference()

    var uri: String? = "rtmp://172.16.0.103/live"
    var streamName: String? = "live"
}
