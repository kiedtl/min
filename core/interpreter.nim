import 
  streams, 
  strutils, 
  json,
  critbits, 
  os,
  algorithm,
  ospaths,
  logging
import 
  value,
  scope,
  parser

type
  MinTrappedException* = ref object of SystemError
  MinRuntimeError* = ref object of SystemError
    data*: MinValue

proc raiseRuntime*(msg: string, data: MinValue) {.extern:"min_exported_symbol_$1".}=
  data[";type"] = %"error"
  raise MinRuntimeError(msg: msg, data: data)

proc dump*(i: MinInterpreter): string {.extern:"min_exported_symbol_$1".}=
  var s = ""
  for item in i.stack:
    s = s & item.str & " "
  return s

proc debug*(i: In, value: MinValue) {.extern:"min_exported_symbol_$1".}=
  debug("(" & i.dump & value.str & ")")

proc debug*(i: In, value: string) {.extern:"min_exported_symbol_$1_2".}=
  debug(value)

template withScope*(i: In, q: MinValue, res:ref MinScope, body: untyped): untyped =
  let origScope = i.scope
  try:
    #TODO Review
    i.scope = new MinScope
    #i.scope = q.scope.copy
    #i.scope.parent = origScope
    body
    res = i.scope
  finally:
    i.scope = origScope

template withScope*(i: In, q: MinValue, body: untyped): untyped =
  let origScope = i.scope
  try:
    #TODO Review
    i.scope = new MinScope
    #i.scope = q.scope.copy
    #i.scope.parent = origScope
    body
    #TODO Review
    #q.scope = i.scope
  finally:
    i.scope = origScope

proc newMinInterpreter*(filename = "input", pwd = ""): MinInterpreter {.extern:"min_exported_symbol_$1".}=
  var path = pwd
  if not pwd.isAbsolute:
    path = joinPath(getCurrentDir(), pwd)
  var stack:MinStack = newSeq[MinValue](0)
  var trace:MinStack = newSeq[MinValue](0)
  var stackcopy:MinStack = newSeq[MinValue](0)
  var pr:MinParser
  var scope = new MinScope
  var i:MinInterpreter = MinInterpreter(
    filename: filename, 
    pwd: path,
    parser: pr, 
    stack: stack,
    trace: trace,
    stackcopy: stackcopy,
    scope: scope
  )
  return i

proc copy*(i: MinInterpreter, filename: string): MinInterpreter {.extern:"min_exported_symbol_$1_2".}=
  var path = filename
  if not filename.isAbsolute:
    path = joinPath(getCurrentDir(), filename)
  result = newMinInterpreter()
  result.filename = filename
  result.pwd =  path.parentDir
  result.stack = i.stack
  result.trace = i.trace
  result.stackcopy = i.stackcopy
  result.scope = i.scope

proc formatError(sym: MinValue, message: string): string {.extern:"min_exported_symbol_$1".}=
  #TODO Review
  return "[$1]: $2" % [sym.str, message]
  #if sym.filename.isNil or sym.filename == "":
  #  return "[$1]: $2" % [sym.symVal, message]
  #else:
  #  return "$1($2,$3) [$4]: $5" % [sym.filename, $sym.line, $sym.column, sym.symVal, message]

proc formatTrace(sym: MinValue): string {.extern:"min_exported_symbol_$1".}=
  #TODO Review
  return "<native> in symbol: $1" % [sym.str]
  #if sym.filename.isNil or sym.filename == "":
  #  return "<native> in symbol: $1" % [sym.symVal]
  #else:
  #  return "$1($2,$3) in symbol: $4" % [sym.filename, $sym.line, $sym.column, sym.symVal]

proc stackTrace(i: In) =
  var trace = i.trace
  trace.reverse()
  for sym in trace:
    notice sym.formatTrace

proc error(i: In, message: string) =
  error(i.currSym.formatError(message))

proc open*(i: In, stream:Stream, filename: string) {.extern:"min_exported_symbol_$1_2".}=
  i.filename = filename
  i.parser.open(stream, filename)

proc close*(i: In) {.extern:"min_exported_symbol_$1_2".}= 
  i.parser.close();

proc push*(i: In, val: MinValue) {.gcsafe, extern:"min_exported_symbol_$1".} 

proc apply*(i: In, op: MinOperator) {.gcsafe, extern:"min_exported_symbol_$1".}=
  var newscope = newScopeRef(i.scope)
  case op.kind
  of minProcOp:
    op.prc(i)
  of minValOp:
    if op.val.kind == JArray:
      var q = op.val
      i.withScope(q, newscope):
        for e in q.elems:
          i.push e
    else:
      i.push(op.val)

proc dequote*(i: In, q: var MinValue) {.extern:"min_exported_symbol_$1".}=
  if not q.isQuotation and not q.isRawDictionary:
    i.push(q)
  else:
    i.withScope(q): 
      for v in q.elems:
        i.push v

proc apply*(i: In, q: var MinValue) {.gcsafe, extern:"min_exported_symbol_$1_2".}=
  var i2 = newMinInterpreter("<apply>")
  i2.trace = i.trace
  i2.scope = i.scope
  try:
    i2.withScope(q): 
      for v in q.elems:
        if (v.isQuotation):
          var v2 = v
          i2.dequote(v2)
        else:
          i2.push v
  except:
    i.currSym = i2.currSym
    i.trace = i2.trace
    raise
  i.push i2.stack.newVal

proc call*(i: In, q: var MinValue): MinValue {.gcsafe, extern:"min_exported_symbol_$1".}=
  var i2 = newMinInterpreter("<call>")
  i2.trace = i.trace
  i2.scope = i.scope
  try:
    i2.withScope(q): 
      for v in q.elems:
        i2.push v
  except:
    i.currSym = i2.currSym
    i.trace = i2.trace
    raise
  return i2.stack.newVal()

proc push*(i: In, val: MinValue) {.gcsafe, extern:"min_exported_symbol_$1".}= 
  if val.isSymbol:
    i.debug(val.str)
    i.trace.add val
    if not i.evaluating:
      i.currSym = val
    let symbol = val.str
    let sigil = "" & symbol[0]
    let found = i.scope.hasSymbol(symbol)
    if found:
      let sym = i.scope.getSymbol(symbol) 
      i.apply(sym)
    else:
      let found = i.scope.hasSigil(sigil)
      if symbol.len > 1 and found:
        let sig = i.scope.getSigil(sigil) 
        let sym = symbol[1..symbol.len-1]
        i.stack.add %sym
        i.apply(sig)
      else:
        raiseUndefined("Undefined symbol '$1'" % [val.str])
    discard i.trace.pop
  else:
    if (val.isRawDictionary):
      var v = val[";raw"]
      i.dequote(v)
      var d = newJObject();
      # TODO Create dictionary based on defined symbols
      i.stack.add(d)
    else:
      i.stack.add(val)

proc pop*(i: In): MinValue {.extern:"min_exported_symbol_$1".}=
  if i.stack.len > 0:
    return i.stack.pop
  else:
    raiseEmptyStack()

proc peek*(i: MinInterpreter): MinValue {.extern:"min_exported_symbol_$1".}= 
  if i.stack.len > 0:
    return i.stack[i.stack.len-1]
  else:
    raiseEmptyStack()

proc interpret*(i: In, parseOnly=false): MinValue {.discardable, extern:"min_exported_symbol_$1".} =
  var val: MinValue
  var q = newSeq[MinValue](0).newVal
  while i.parser.token != tkEof: 
    if i.trace.len == 0:
      i.stackcopy = i.stack
    try:
      val = i.parser.parseMinValue(i)
      if parseOnly:
        q.add val
      else:
        i.push val
    except MinRuntimeError:
      let msg = getCurrentExceptionMsg()
      i.stack = i.stackcopy
      #TODO Review
      error(msg)
      #error("$1:$2,$3 $4" % [i.currSym.filename, $i.currSym.line, $i.currSym.column, msg])
      i.stackTrace
      i.trace = @[]
      raise MinTrappedException(msg: msg)
    except MinTrappedException:
      raise
    except:
      let msg = getCurrentExceptionMsg()
      i.stack = i.stackcopy
      i.error(msg)
      i.stackTrace
      i.trace = @[]
      raise MinTrappedException(msg: msg)
  if parseOnly:
    return q
  if i.stack.len > 0:
    return i.stack[i.stack.len - 1]

proc eval*(i: In, s: string, name="<eval>", parseOnly=false): MinValue {.discardable, extern:"min_exported_symbol_$1".}=
  var i2 = i.copy(name)
  i2.open(newStringStream(s), name)
  discard i2.parser.getToken() 
  result = i2.interpret(parseOnly)
  i.trace = i2.trace
  i.stackcopy = i2.stackcopy
  i.stack = i2.stack
  i.scope = i2.scope

proc load*(i: In, s: string, parseOnly=false): MinValue {.discardable, extern:"min_exported_symbol_$1".}=
  var i2 = i.copy(s)
  i2.open(newStringStream(s.readFile), s)
  discard i2.parser.getToken() 
  result = i2.interpret(parseOnly)
  i.trace = i2.trace
  i.stackcopy = i2.stackcopy
  i.stack = i2.stack
  i.scope = i2.scope

proc parse*(i: In, s: string, name="<parse>"): MinValue {.extern:"min_exported_symbol_$1".}=
  return i.eval(s, name, true)

proc read*(i: In, s: string): MinValue {.extern:"min_exported_symbol_$1".}=
  return i.load(s, true)

