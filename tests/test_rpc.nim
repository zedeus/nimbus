import
  unittest, json, strformat, nimcrypto, rlp, options, macros, typetraits,
  json_rpc/[rpcserver, rpcclient],
  ../nimbus/rpc/[common, p2p, hexstrings, rpc_types],
  ../nimbus/constants,
  ../nimbus/nimbus/[vm_state, config],
  ../nimbus/db/[state_db, db_chain], eth_common, byteutils,
  ../nimbus/p2p/chain,
  ../nimbus/genesis,  
  eth_trie/db,
  eth_p2p, eth_keys,
  rpcclient/test_hexstrings

# Perform checks for hex string validation
doHexStrTests()

from os import getCurrentDir, DirSep
from strutils import rsplit
template sourceDir: string = currentSourcePath.rsplit(DirSep, 1)[0]

## Generate client convenience marshalling wrappers from forward declarations
## For testing, ethcallsigs needs to be kept in sync with ../nimbus/rpc/[common, p2p]
const sigPath = &"{sourceDir}{DirSep}rpcclient{DirSep}ethcallsigs.nim"
createRpcSigs(RpcSocketClient, sigPath)

proc setupEthNode: EthereumNode =
  var
    conf = getConfiguration()
    keypair: KeyPair
  keypair.seckey = conf.net.nodekey
  keypair.pubkey = conf.net.nodekey.getPublicKey()

  var srvAddress: Address
  srvAddress.ip = parseIpAddress("0.0.0.0")
  srvAddress.tcpPort = Port(conf.net.bindPort)
  srvAddress.udpPort = Port(conf.net.discPort)
  result = newEthereumNode(keypair, srvAddress, conf.net.networkId,
                              nil, "nimbus 0.1.0")

proc toEthAddressStr(address: EthAddress): EthAddressStr =
  result = ("0x" & address.toHex).ethAddressStr

proc doTests =
  # TODO: Include other transports such as Http
  var ethNode = setupEthNode()
  let
    emptyRlpHash = keccak256.digest(rlp.encode(""))
    header = BlockHeader(stateRoot: emptyRlpHash)
  var
    chain = newBaseChainDB(newMemoryDb())
    state = newBaseVMState(header, chain)
  ethNode.chain = newChain(chain)

  let
    balance = 100.u256
    address: EthAddress = hexToByteArray[20]("0x0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6")
    conf = getConfiguration()
  defaultGenesisBlockForNetwork(conf.net.networkId.toPublicNetwork()).commit(chain)
  state.mutateStateDB:
    db.setBalance(address, balance)
  
  # Create Ethereum RPCs
  var
    rpcServer = newRpcSocketServer(["localhost:8545"])
    client = newRpcSocketClient()
  setupCommonRpc(rpcServer)
  setupEthRpc(ethNode, chain, rpcServer)

  # Begin tests
  rpcServer.start()
  waitFor client.connect("localhost", Port(8545))

  macro makeTest(callName: untyped, data: untyped): untyped =
    ## Generate generic testing code for checking rpcs.
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

  let currentBlockNumber = "0x" & state.blockheader.blockNumber.toHex

  suite "Remote Procedure Calls":

    makeTest(eth_blockNumber):
      expected: 0

    makeTest(eth_call):
      params:
        EthCall(value: some(100.u256))
        currentBlockNumber

    makeTest(eth_getBalance):
      params:
        ZERO_ADDRESS.toEthAddressStr
        "0x0"
      expected: balance
    
    makeTest(eth_getStorageAt):
      params:
        address.toEthAddressStr
        0
        currentBlockNumber

  rpcServer.stop()
  rpcServer.close()

doTests()
