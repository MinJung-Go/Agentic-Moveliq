import Foundation

struct CoachToolResult {
    var content: String
    var sources: [URL] = []
    var failed = false
    var sourcePreviews: [PublicSourcePreview] = []
}


/// Display metadata stays separate from the bounded text sent to the model.
struct PublicSourcePreview: Identifiable {
    var url: URL
    var title: String
    var summary: String
    var id: URL { url }
}
