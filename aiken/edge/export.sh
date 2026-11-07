#!/bin/bash
# Export every edge-case function as DATA_DIR/Edge<Name>/aiken.cbor.hex.
set -euo pipefail
cd "$(dirname "$0")"
DATA=${1:-/Users/sho/fun/cross-bench-data}
for entry in ListSum:list_sum MapFilterCount:map_filter_count WideRecord:wide_record \
  ValueLookup:value_lookup EnumDispatch:enum_dispatch GuardOrder:guard_order \
  ByteSearch:byte_search NestedLists:nested_lists Horner:horner AllAny:all_any; do
  name=${entry%%:*}
  fn=${entry#*:}
  mkdir -p "$DATA/Edge$name"
  aiken export -m "edge/$fn" -n "$fn" -t silent 2>/dev/null |
    python3 -c 'import json,sys; c=json.load(sys.stdin)["compiledCode"]; open(sys.argv[1],"w").write(c+"\n"); print(sys.argv[2], len(c)//2, "bytes")' \
      "$DATA/Edge$name/aiken.cbor.hex" "Edge$name"
done
