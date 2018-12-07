import
  unittest, json, strformat, nimcrypto, rlp, options, macros, typetraits,
  json_rpc/[rpcserver, rpcclient],
  ../nimbus/rpc/[common, p2p, hexstrings, rpc_types],
  ../nimbus/constants,
  ../nimbus/nimbus/[vm_state, config],
  ../nimbus/db/[state_db, db_chain], eth_common, byteutils,
  ../nimbus/p2p/chain,
  ../nimbus/genesis, ../nimbus/utils/header,
  eth_trie/db,
  eth_p2p, eth_keys,
  rpcclient/[test_hexstrings, rpctesting]

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

func toAddressStr(address: EthAddress): string =
  result = "0x" & address.toHex

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

  # Initialise state
  let
    balance = 100.u256
    address: EthAddress = hexToByteArray[20]("0x0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6")
    addressHexStr = address.toAddressStr
    conf = getConfiguration()
  defaultGenesisBlockForNetwork(conf.net.networkId.toPublicNetwork()).commit(chain)
  state.mutateStateDB:
    db.setBalance(address, balance)

  # Future tests may update the block number
  func currentBlockNumber: BlockNumber = chain.getCanonicalHead.blockNumber
  func currentBlockNumberStr: string = "0x" & currentBlockNumber().toHex
  
  # Create Ethereum RPCs
  var
    rpcServer = newRpcSocketServer(["localhost:8545"])
    client = newRpcSocketClient()
  setupCommonRpc(rpcServer)
  setupEthRpc(ethNode, chain, rpcServer)

  # Begin tests
  rpcServer.start()
  waitFor client.connect("localhost", Port(8545))

  suite "Remote Procedure Calls":

    rpcTest(eth_blockNumber):
      expected: 0

    rpcTest(eth_call):
      params:
        EthCall(value: some(100.u256))
        currentBlockNumberStr()

    rpcTest(eth_getBalance):
      params:
        ZERO_ADDRESS.toAddressStr
        "0x0"
      expected: balance
    
    rpcTest(eth_getStorageAt):
      params:
        addressHexStr
        0
        currentBlockNumberStr()
      expected: "0x0"

    rpcTest(eth_getTransactionCount):
      params:
        addressHexStr
        currentBlockNumberStr()
      expected: 0

    rpcTest(eth_getBlockTransactionCountByHash):
      params: "0x" & chain.getCanonicalHead.hash.data.toHex
      expected: 0

    rpcTest(eth_getBlockTransactionCountByNumber):
      params: currentBlockNumberStr()
      expected: 0

    rpcTest(eth_getCode):
      params:
        addressHexStr
        currentBlockNumberStr()
      expected: "0x0"

  rpcServer.stop()
  rpcServer.close()

doTests()
