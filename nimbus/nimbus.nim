# Nimbus
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import strutils
import asyncdispatch2, eth-rpc/server
import config, rpc/common

when isMainModule:
  var message: string
  echo NimbusHeader
  if processArguments(message) != ConfigStatus.Success:
    echo message
    quit(QuitFailure)
  else:
    if len(message) > 0:
      echo message

  var conf = getConfiguration()
  if RpcFlags.Enabled in conf.rpc.flags:
    var rpcserver = newRpcServer(conf.rpc.binds)
    setupCommonRPC(rpcserver)
    rpcserver.start()

  while true:
    poll()
