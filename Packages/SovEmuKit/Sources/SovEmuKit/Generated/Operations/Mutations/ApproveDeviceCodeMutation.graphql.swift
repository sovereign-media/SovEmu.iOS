// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ApproveDeviceCodeMutation: GraphQLMutation {
    static let operationName: String = "ApproveDeviceCode"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation ApproveDeviceCode($code: String!) { approveDeviceCode(userCode: $code) }"#
      ))

    public var code: String

    public init(code: String) {
      self.code = code
    }

    @_spi(Unsafe) public var __variables: Variables? { ["code": code] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("approveDeviceCode", Bool.self, arguments: ["userCode": .variable("code")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ApproveDeviceCodeMutation.Data.self
      ] }

      /// Signs a TV in as you: the code its *Sign in with your phone* screen shows, typed on a
      /// phone or tablet already signed in here (*Sign in a TV*), or on the web client's `/link/`
      /// page, where the TV sends people. `NOT_FOUND` when no TV is waiting with that code;
      /// `TOO_MANY_REQUESTS` after several wrong ones.
      var approveDeviceCode: Bool { __data["approveDeviceCode"] }
    }
  }

}