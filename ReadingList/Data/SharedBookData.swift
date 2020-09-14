import Foundation
import PersistedPropertyWrapper

struct SharedBookData: Codable {
    let title: String
    let authorDisplay: String
    let identifier: BookIdentifier
    let coverImage: Data

    @Persisted(encodedDataKey: "sharedBooks", defaultValue: [], storage: .appExtensionShared)
    static var sharedBooks: [SharedBookData]
}

extension UserDefaults {
    static var appExtensionShared = UserDefaults(suiteName: "com.andrewbennet.books.shared")!
}

extension BookIdentifier: Codable {
    enum CodingKeys: CodingKey {
        case googleBooksId, manualId, isbn
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .googleBooksId(let googleBooksId):
            try container.encode(googleBooksId, forKey: .googleBooksId)
        case .manualId(let manualId):
            try container.encode(manualId, forKey: .manualId)
        case .isbn(let isbn):
            try container.encode(isbn, forKey: .isbn)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch container.allKeys.first! {
        case .googleBooksId:
            self = .googleBooksId(try container.decode(String.self, forKey: .googleBooksId))
        case .manualId:
            self = .manualId(try container.decode(String.self, forKey: .manualId))
        case .isbn:
            self = .isbn(try container.decode(String.self, forKey: .isbn))
        }
    }
}
