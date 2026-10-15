import Observation

enum Route: Hashable {
    case review, people, assign, summary
}

@Observable
final class Router {
    var path: [Route] = []
}
