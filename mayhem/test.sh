#!/usr/bin/env bash
#
# mayhem/test.sh — RUN cmark's own suite (built by mayhem/build.sh in build/tests) via ctest, then
# known-answer probes that invoke the built `cmark` binary directly and compare exact output. ctest
# alone judges by exit codes only, so the probes are what makes a neutered program fail this oracle.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build/tests/src/cmark"
[ -x "$BIN" ] || { echo "missing $BIN — mayhem/build.sh should have built it" >&2; emit_ctrf cmark-ctest+kat 0 1; exit 1; }

passed=0; failed=0
out="$(cd build/tests && ctest 2>&1)"; echo "$out"
if [[ "$out" =~ ([0-9]+)\ tests\ failed\ out\ of\ ([0-9]+) ]]; then
  failed=${BASH_REMATCH[1]}; passed=$(( ${BASH_REMATCH[2]} - failed ))
  [ "${BASH_REMATCH[2]}" -gt 0 ] || failed=$((failed+1))
else
  failed=$((failed+1))
fi

kat() { # kat <name> <expected> <input> [cmark args...]
  local name="$1" expected="$2" input="$3"; shift 3
  local got; got="$(printf '%s' "$input" | "$BIN" "$@" 2>&1)"
  if [ "$got" == "$expected" ]; then passed=$((passed+1)); else
    failed=$((failed+1)); echo "KAT FAIL $name: expected [$expected] got [$got]" >&2; fi
}
kat heading   '<h1>Hello <em>world</em></h1>' $'# Hello *world*\n'
kat link      '<p><a href="http://x.example/" title="t">a &amp; b</a></p>' $'[a & b](http://x.example/ "t")\n'
kat smart     '<p>“q” – x…</p>' $'"q" -- x...\n' --smart
kat commonmark $'  - a\n  - b' $'* a\n* b\n' -t commonmark
kat code      '<pre><code class="language-c">int x;
</code></pre>' $'```c\nint x;\n```\n'
got="$(printf '3. a\n4. b\n' | "$BIN" -t xml | grep '<list ')"
[ "$got" == '  <list type="ordered" start="3" delimiter="period" tight="true">' ] \
  && passed=$((passed+1)) || { failed=$((failed+1)); echo "KAT FAIL list-xml: [$got]" >&2; }

emit_ctrf cmark-ctest+kat "$passed" "$failed"
