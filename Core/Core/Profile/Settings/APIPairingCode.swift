//
// This file is part of Canvas.
// Copyright (C) 2020-present  Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

public struct PostObserverPairingCodes: APIRequestable {
    public typealias Response = APIPairingCode
    public var method: APIMethod = .post
    public var path: String = "users/self/observer_pairing_codes"
}

public struct APIPairingCode: Codable, Equatable {
    let user_id: ID?
    let code: String
    let expires_at: Date?
    let workflow_state: String?
}

public struct GetAccountTermsOfServiceRequest: APIRequestable {
    public typealias Response = APIAccountTermsOfService
    public var path: String = "accounts/self/terms_of_service"
}

public struct APIAccountTermsOfService: Codable, Equatable {
    let account_id: ID
    let content: String?
    let id: ID?
    let passive: Bool?
    let terms_type: String?
}

//  https://canvas.instructure.com/doc/api/users.html#method.users.create
public struct PostAccountUserRequest: APIRequestable {
    public typealias Response = APIUser
    public let method: APIMethod = .post
    public var path: String { "accounts/\(accountID)/users" }
    public var body: Body?
    let baseURL: URL
    let accountID: String

    public init(baseURL: URL, accountID: String, pairingCode: String, name: String, email: String, password: String) {
        self.baseURL = baseURL
        self.accountID = accountID
        self.body = Body(
            pseudonym: Body.Pseudonym(unique_id: email, password: password),
            pairing_code: Body.PairingCode(code: pairingCode),
            user: Body.User(name: name, initial_enrollment_type: "observer")
        )
    }

    public struct Body: Codable, Equatable {
        public struct Pseudonym: Codable, Equatable {
            let unique_id: String
            let password: String
        }
        public struct PairingCode: Codable, Equatable {
            let code: String
        }
        public struct User: Codable, Equatable {
            let name: String
            let initial_enrollment_type: String
            let terms_of_use: Bool = true
        }
        let pseudonym: Pseudonym
        let pairing_code: PairingCode
        let user: User
    }

    public func urlRequest(relativeTo baseURL: URL, accessToken: String?, actAsUserID: String?) throws -> URLRequest {
        guard var components = URLComponents(string: path) else { throw APIRequestableError.invalidPath(path) }

        if !path.hasPrefix("/") && components.host == nil {
            components.path = "/api/v1/" + components.path
        }

        let queryItems = self.queryItems
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let url = components.url(relativeTo: self.baseURL) else { throw APIRequestableError.cannotResolve(components, self.baseURL) }

        var request: URLRequest
        request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method.rawValue.uppercased()

        if let body = self.body {
            request.httpBody = try encode(body)
            request.setValue("application/json", forHTTPHeaderField: HttpHeader.contentType)
        }

        request.setValue("application/json+canvas-string-ids", forHTTPHeaderField: HttpHeader.accept)
        request.setValue(UserAgent.default.description, forHTTPHeaderField: HttpHeader.userAgent)

        return request
    }
}

#if DEBUG
extension APIPairingCode {
    public static func make(
        user_id: ID? = "1",
        code: String = "code",
        expires_at: Date? = Clock.now,
        workflow_state: String? = "active"
    ) -> APIPairingCode {
        return APIPairingCode(
            user_id: user_id,
            code: code,
            expires_at: expires_at,
            workflow_state: workflow_state
        )
    }
}

extension APIAccountTermsOfService {
    public static func make(
        account_id: ID = "1",
        content: String? = "content",
        id: ID? = nil,
        passive: Bool? = false,
        terms_type: String? = nil
    ) -> APIAccountTermsOfService {
        return APIAccountTermsOfService(
            account_id: account_id,
            content: content,
            id: id,
            passive: passive,
            terms_type: terms_type
        )
    }
}
#endif
