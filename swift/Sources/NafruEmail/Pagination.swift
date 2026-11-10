import Foundation

/// Bir liste çağrısını tüm sayfalar boyunca gezer (`after` imleci, en yeni önce sırasında ileri). Hata gelirse dizi o hatayı
/// fırlatır: sayfalama döngüsünde sessizce kesmek eksik veri okutur.
///
///     for try await contact in paginate(nafru.contacts.list, ListContactsQuery(limit: 100)) { … }
public func paginate<Query: PageableQuery, Item: Decodable & Sendable & Identifiable>(
    _ list: @escaping (Query) async throws -> ListResponse<Item>,
    _ query: Query
) -> AsyncThrowingStream<Item, Error> where Item.ID == String {
    AsyncThrowingStream { continuation in
        let task = Task {
            var query = query
            query.after = nil
            do {
                while true {
                    let page = try await list(query)
                    for item in page.data { continuation.yield(item) }
                    guard page.hasMore, let last = page.data.last else { break }
                    query.after = last.id
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
