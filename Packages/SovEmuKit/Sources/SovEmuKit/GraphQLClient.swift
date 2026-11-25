import Apollo
import ApolloAPI
import Foundation

// MARK: - The Apollo client: one per server, with the bearer token on every request

/// Builds the `ApolloClient` for one server. There is no normalized cache: every query is
/// `networkOnly` and nothing is written to the store, as on Android, whose Apollo client has no
/// cache configured.
enum GraphQLClient {
    /// A client for `baseURL`'s `/graphql`, sending `auth`'s access token (none when `auth` is
    /// nil: the anonymous `bootstrapConfig`).
    static func make(baseURL: URL, auth: TokenClient?, session: URLSession) -> ApolloClient {
        let store = ApolloStore(cache: InMemoryNormalizedCache())
        let transport = RequestChainNetworkTransport(
            urlSession: session,
            interceptorProvider: Interceptors(auth: auth),
            store: store,
            endpointURL: baseURL.appending(path: "graphql")
        )
        return ApolloClient(
            networkTransport: transport,
            store: store,
            defaultRequestConfiguration: RequestConfiguration(requestTimeout: 30, writeResultsToCache: false),
            // The server has no use for Apollo's client-awareness headers and extensions.
            clientAwarenessMetadata: .none
        )
    }
}

/// The interceptors every operation runs through: no automatic persisted queries (the server does
/// not take them) and no retries beyond the one `BearerInterceptor` spends. `MaxRetryInterceptor`
/// sits first anyway, as Apollo advises, so a bug that kept retrying could not loop forever.
struct Interceptors: InterceptorProvider {
    let auth: TokenClient?

    func graphQLInterceptors<Operation: GraphQLOperation>(for _: Operation) -> [any GraphQLInterceptor] {
        var interceptors: [any GraphQLInterceptor] = [MaxRetryInterceptor(maxRetriesAllowed: 1)]
        if let auth { interceptors.append(BearerInterceptor(auth: auth)) }
        return interceptors
    }
}

/// Sends `Authorization: Bearer` with a current access token (none when signed out), and recovers
/// from one authentication failure: when the server says `UNAUTHENTICATED` (or answers 401) to a
/// token, it refreshes the token and sends the operation once more.
///
/// The provider makes a new interceptor for each operation, so `retried` is per operation. The
/// retry is Apollo's own (`RequestChain.Retry`), which runs the chain again from the start: this
/// interceptor then reads the token `refresh` has just stored. A refused refresh ends the
/// sign-in, and is reported as the API would report it, `UNAUTHENTICATED`.
actor BearerInterceptor: GraphQLInterceptor {
    private let auth: TokenClient
    private var retried = false

    init(auth: TokenClient) { self.auth = auth }

    func intercept<Request: GraphQLRequest>(
        request: Request,
        next: NextInterceptorFunction<Request>
    ) async throws -> InterceptorResultStream<Request> {
        let token: String?
        do {
            token = try await auth.accessToken()
        } catch {
            throw APIError.refused(error)
        }
        var request = request
        request.additionalHeaders["Authorization"] = token.map { "Bearer \($0)" }
        let sent = request
        // Only a token can be refused: signed out, an `UNAUTHENTICATED` is the answer itself.
        let mayRetry = !retried && token != nil

        return await next(sent)
            .map { [self] parsed in
                guard mayRetry, APIError.isUnauthenticated(parsed.result.errors) else { return parsed }
                try await refresh(replacing: token)
                throw RequestChain<Request>.Retry(request: sent)
            }
            .mapErrors { [self] error in
                guard mayRetry, (error as? ResponseCodeInterceptor.ResponseCodeError)?.response.statusCode == 401 else {
                    throw error
                }
                try await refresh(replacing: token)
                throw RequestChain<Request>.Retry(request: sent)
            }
    }

    /// Spends this operation's one retry on a refresh.
    private func refresh(replacing token: String?) async throws {
        retried = true
        do {
            _ = try await auth.refresh(replacing: token)
        } catch {
            throw APIError.refused(error)
        }
    }
}

extension GraphQLNullable {
    /// The value, or an explicit **`null`** (never absent): what the server reads as "none" for
    /// an argument such as `system` (every system) or `patchId` (the original game).
    static func orNull(_ value: Wrapped?) -> GraphQLNullable<Wrapped> {
        value.map { .some($0) } ?? .null
    }
}

// MARK: - Failures

extension APIError {
    /// The `extensions.code` that means "not signed in, or the token is no longer good".
    static let unauthenticated = "UNAUTHENTICATED"

    static func isUnauthenticated(_ errors: [GraphQLError]?) -> Bool {
        errors?.contains { $0.extensions?["code"] as? String == unauthenticated } ?? false
    }

    /// The first of an answer's GraphQL errors, with its `extensions.code`.
    init(_ error: GraphQLError) {
        self.init(
            status: 200, code: error.extensions?["code"] as? String,
            message: error.message ?? "The server refused the request.")
    }

    /// A non-2xx answer: its GraphQL error when the body has one, else the status.
    init(_ failure: ResponseCodeInterceptor.ResponseCodeError) {
        let status = failure.response.statusCode
        struct Body: Decodable {
            struct Failure: Decodable {
                struct Extensions: Decodable { let code: String? }
                let message: String
                let extensions: Extensions?
            }
            let errors: [Failure]?
        }
        if let first = (try? JSONDecoder().decode(Body.self, from: failure.chunk))?.errors?.first {
            self.init(status: status, code: first.extensions?.code, message: first.message)
        } else {
            self.init(status: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
        }
    }

    /// A refused refresh is the end of the sign-in: report it as `UNAUTHENTICATED`, as the API
    /// would, so callers have one thing to check. Other failures (offline) pass through.
    static func refused(_ error: any Error) -> any Error {
        guard let error = error as? AuthError, error.isInvalidGrant || error == .signedOut else { return error }
        return APIError(status: 401, code: unauthenticated, message: error.message ?? "Sign in again.")
    }
}
