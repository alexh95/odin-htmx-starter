#!/bin/sh
# Every app package with a _test.odin outside cmd/ (the profiles test through
# `CMD=test build.sh <p>`), plus tools/check, under the test runner's memory
# tracking with bad memory fatal: 0 leaks, 0 bad frees (PLAN §19.1.1). A package
# that reaches platform/web (stream, hub) reaches the family collections through
# platform/html, so every package tests on minimal's four; the rest import none.
#
# Usage: sh .github/scripts/unit-tests.sh   (from the repo root)
set -eu
fail=0
for d in $(find app tools/check tools/fakellama -name '*_test.odin' -not -path 'app/vendor/sqlite/*' -not -path 'app/cmd/*' -not -path '*/testdata/*' | xargs -n1 dirname | sort -u); do
  echo "== odin test $d"
  odin test "$d" -collection:store=app/stores/memory -collection:identity=app/platform/authz/anonymous \
    -collection:client=app/platform/client/vanilla -collection:theme=app/platform/theme/lite \
    -vet -vet-cast -vet-semicolon -vet-tabs -vet-using-param -disallow-do -strict-style -warnings-as-errors -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
    -out:"app/bin/unit-test$(case "$(uname -s)" in *MINGW*|*MSYS*|*CYGWIN*) echo .exe ;; esac)" || fail=1
done
exit "$fail"
