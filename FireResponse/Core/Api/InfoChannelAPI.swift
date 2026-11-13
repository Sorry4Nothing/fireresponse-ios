import Foundation

/// Aufrufe des Infokanals. Die Kennungen gehen nur als UUID hinaus (`Endpoint.accepts`), nie als beliebiger Text.
nonisolated protocol InfoChannelService: Sendable {
    func infoChannels() async -> ApiResult<InfoChannelList>
    func infoMessages(unitId: String, before: String?, limit: Int) async -> ApiResult<InfoMessagePage>
    func postInfoMessage(unitId: String, text: String) async -> ApiResult<InfoMessage>
    func editInfoMessage(unitId: String, messageId: String, text: String) async -> ApiResult<InfoMessage>
    func deleteInfoMessage(unitId: String, messageId: String) async -> ApiResult<Void>
    func markInfoRead(unitId: String) async -> ApiResult<Void>
}

nonisolated extension FireResponseAPI: InfoChannelService {
    func infoChannels() async -> ApiResult<InfoChannelList> {
        await client.send(.infoChannels)
    }

    func infoMessages(unitId: String, before: String?, limit: Int) async -> ApiResult<InfoMessagePage> {
        var query = "?limit=\(min(max(limit, 1), 100))"
        if let before { query += "&vor=\(before)" }
        return decode(await client.perform(.infoMessages, rawPath: Endpoint.infoMessages.path(unitId) + query))
    }

    func postInfoMessage(unitId: String, text: String) async -> ApiResult<InfoMessage> {
        decode(await client.perform(.postInfoMessage, rawPath: Endpoint.postInfoMessage.path(unitId), body: .json(InfoTextBody(text: text))))
    }

    func editInfoMessage(unitId: String, messageId: String, text: String) async -> ApiResult<InfoMessage> {
        decode(await client.perform(.editInfoMessage, rawPath: Endpoint.editInfoMessage.path(unitId, messageId), body: .json(InfoTextBody(text: text))))
    }

    func deleteInfoMessage(unitId: String, messageId: String) async -> ApiResult<Void> {
        await client.perform(.deleteInfoMessage, rawPath: Endpoint.deleteInfoMessage.path(unitId, messageId)).map { _ in () }
    }

    func markInfoRead(unitId: String) async -> ApiResult<Void> {
        await client.perform(.markInfoRead, rawPath: Endpoint.markInfoRead.path(unitId)).map { _ in () }
    }

    private func decode<T: Decodable & Sendable>(_ result: ApiResult<Data>) -> ApiResult<T> {
        switch result {
        case .ok(let data):
            do { return .ok(try JSONDecoder.api.decode(T.self, from: data)) } catch { return .failure(.unknown) }
        case .failure(let error, let code, let retry):
            return .failure(error, code: code, retryAfterSeconds: retry)
        }
    }
}
