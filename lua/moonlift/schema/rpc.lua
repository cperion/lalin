local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonRpc {
  product. JsonMember { key [str], field "value" [ty "MoonRpc.JsonValue"], },
  sum. JsonValue {
    JsonNull,
    JsonBool { field "value" [bool], },
    JsonNumber { raw [str], },
    JsonString { field "value" [str], },
    JsonArray { values [many [ty "MoonRpc.JsonValue"]], },
    JsonObject { members [many [ty "MoonRpc.JsonMember"]], },
  },
  sum. Incoming {
    RpcRequest {
      field "id" [ty "MoonEditor.RpcId"],
      method [str],
      params [ty "MoonRpc.JsonValue"],
    },
    RpcIncomingNotification { method [str], params [ty "MoonRpc.JsonValue"], },
    RpcInvalid { reason [str], },
  },
  sum. Outgoing {
    RpcResult { field "id" [ty "MoonEditor.RpcId"], payload [ty "MoonLsp.Payload"], },
    RpcError { field "id" [ty "MoonEditor.RpcId"], code [number], message [str], },
    RpcOutgoingNotification { method [str], payload [ty "MoonLsp.Payload"], },
  },
  sum. OutCommand {
    SendMessage { outgoing [ty "MoonRpc.Outgoing"], },
    LogMessage { level [str], message [str], },
    StopServer,
  },
}
