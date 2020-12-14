when not defined(mini):
  import os
  var HOME*: string
  if defined(windows):
    HOME = getenv("USERPROFILE")
  if not defined(windows):
    HOME = getenv("HOME")

  var MINRC* {.threadvar.}: string
  MINRC = HOME / ".minrc" 
  var MINSYMBOLS* {.threadvar.}: string 
  MINSYMBOLS = HOME / ".min_symbols"
  var MINHISTORY* {.threadvar.}: string
  MINHISTORY = HOME / ".min_history"
  var MINLIBS* {.threadvar.} : string
  MINLIBS  = HOME / ".minlibs"

var MINCOMPILED* {.threadvar.}: bool
MINCOMPILED = false
var MINSERVER* {.threadvar.}: bool
MINSERVER = false
