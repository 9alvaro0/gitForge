import Foundation
import Testing
@testable import gitForge

@Suite("Write errors and requests")
struct PullRequestActionErrorTests {
    @Test("HTTP failures map to action errors", arguments: [
        (PullRequestFetchError.forbidden, PullRequestActionError.forbidden),
        (.notFound, .changedOnHost),
        (.server(409, "{}"), .headChanged),
        (.server(422, #"{"message":"Unprocessable","errors":["User can only have one pending review per pull request"]}"#), .pendingReview),
        (.server(405, #"{"message":"Pull Request is not mergeable"}"#), .rejected("Pull Request is not mergeable")),
        (.server(406, #"{"message":{"base":["Branch cannot be merged"]}}"#), .rejected("Branch cannot be merged")),
        (.server(422, #"{"error":"sha does not match"}"#), .rejected("sha does not match")),
        (.server(500, "boom"), .other("Server returned 500: boom")),
        (.server(422, #"{"message":"Unprocessable Entity","errors":["Can not approve your own pull request"]}"#),
         .rejected("Can not approve your own pull request")),
        (.server(422, #"{"message":"Validation Failed","errors":[{"resource":"PullRequestReview","code":"custom","message":"Commit id is not part of the pull request"}]}"#),
         .rejected("Commit id is not part of the pull request")),
    ])
    func mapping(input: PullRequestFetchError, expected: PullRequestActionError) {
        #expect(PullRequestActionError.from(input) == expected)
    }

    @Test("A body that isn't JSON is quoted, cut to 200 characters")
    func plainBody() {
        let long = String(repeating: "x", count: 250)
        #expect(PullRequestActionError.hostMessage(fromBody: "  Nope \n") == "Nope")
        #expect(PullRequestActionError.hostMessage(fromBody: long).count == 200)
    }

    @Test("Forbidden names the account, host and action, per noun")
    func forbiddenCopy() {
        #expect(PullRequestActionError.forbidden.message(for: .approve, account: "octo", host: "github.com", isMergeRequest: false)
                == "Your account (octo on github.com) can't approve this pull request.")
        #expect(PullRequestActionError.forbidden.message(for: .merge, account: "marta", host: "gitlab.example.test", isMergeRequest: true)
                == "Your account (marta on gitlab.example.test) can't merge this merge request.")
    }

    @Test("Head changes read differently for merges")
    func headChangedCopy() {
        #expect(PullRequestActionError.headChanged.message(for: .merge, account: nil, host: "github.com", isMergeRequest: false)
                == "New commits were pushed — review them before merging.")
        #expect(PullRequestActionError.headChanged.message(for: .approve, account: nil, host: "github.com", isMergeRequest: false)
                == "New commits were pushed — review them and try again.")
        #expect(PullRequestActionError.rejected("Not allowed").message(for: .approve, account: nil, host: "h", isMergeRequest: false)
                == "The host refused: Not allowed")
    }

    @Test("JSON body and method are set; GraphQL errors throw")
    func requests() throws {
        let base = URLRequest(url: URL(string: "https://api.github.com/x")!)
        let request = RemoteAPI.withJSON(base, method: "POST", body: ["event": "APPROVE"])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String] == ["event": "APPROVE"])
        struct Payload: Decodable { let ok: Bool }
        #expect(throws: PullRequestFetchError.server(200, "Field 'nope' doesn't exist")) {
            try RemoteAPI.decodeGraphQL(Data(#"{"errors":[{"message":"Field 'nope' doesn't exist"}]}"#.utf8), as: Payload.self)
        }
        #expect(try RemoteAPI.decodeGraphQL(Data(#"{"data":{"ok":true}}"#.utf8), as: Payload.self).ok)
    }

    @Test("GraphQL requests post the query and variables with the base's headers")
    func graphQLRequest() throws {
        var base = URLRequest(url: URL(string: "https://api.github.com/x")!)
        base.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        let request = RemoteAPI.graphQL(base, endpoint: URL(string: "https://api.github.com/graphql")!,
                                        query: "query { viewer { login } }", variables: ["id": "PRRT_1"])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["query"] as? String == "query { viewer { login } }")
        #expect(json["variables"] as? [String: String] == ["id": "PRRT_1"])
    }

    @Test("References read #N on GitHub and !N on GitLab")
    func references() {
        #expect(RemoteProvider.github.reference(42) == "#42")
        #expect(RemoteProvider.gitlab.reference(42) == "!42")
    }
}
