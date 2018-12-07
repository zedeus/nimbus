import macros

macro rpcTest*(callName: untyped, data: untyped): untyped =
  ## Generate generic testing code for checking rpcs.
  ## Note that this assumes you have used signatures to generate RPC procs.
  result = newStmtList()

  let
    testName = $callName
    rpcResult = newIdentNode "r"
    resultTitle = "RPC \"" & testName & "\" returned: "
  var
    call = nnkCall.newTree()
    expectedResult: NimNode

  call.add(nnkDotExpr.newTree(ident "client", ident testName))
  
  for node in data.children:
    if node.len > 1 and node.kind == nnkCall and node[0].kind == nnkIdent and
      node[1].kind == nnkStmtList and node[1].len > 0:
        case $node[0]
        of "params":
          for param in node[1].children:
            call.add(param)
        of "expected":
          let res = node[1][0]
          # TODO: Expect failure
          expectedResult = quote do:
            check `rpcResult` == `res`
        
  if expectedResult == nil:
    expectedResult = quote do: echo "[Result is not checked]"

  result = quote do:
    test `testName`: 
      var `rpcResult` = waitFor `call`
      echo `resultTitle`, `rpcResult`, " (type: ", `rpcResult`.type.name, ")"
      `expectedResult`