#!/usr/bin/env bash
# Shared JUnit XML helpers for CI scripts. Source this file; do not execute directly.
# Callers accumulate test cases via junit_pass / junit_fail, then call junit_write.
#
# State variables (managed by these functions):
#   _JUNIT_TC_XML  — accumulated <testcase> XML fragments
#   _JUNIT_TESTS   — total test count
#   _JUNIT_FAILURES — failure count

_JUNIT_TC_XML=""
_JUNIT_TESTS=0
_JUNIT_FAILURES=0

# Portable nanosecond-or-second timestamp.
junit_ts() { date +%s%N 2>/dev/null || date +%s; }

# Convert two timestamps (from junit_ts) to a decimal-seconds string.
junit_duration() {
  local t_start="$1" t_end="$2"
  if [ ${#t_start} -gt 10 ]; then
    awk "BEGIN{printf \"%.3f\", ($t_end - $t_start)/1000000000}"
  else
    echo $(( t_end - t_start ))
  fi
}

# Escape text for safe inclusion inside XML elements/attributes.
junit_xml_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

# Record a passing test case.
# Usage: junit_pass CLASSNAME NAME DURATION
junit_pass() {
  local classname="$1" name="$2" duration="$3"
  _JUNIT_TESTS=$((_JUNIT_TESTS + 1))
  _JUNIT_TC_XML="${_JUNIT_TC_XML}<testcase classname=\"${classname}\" name=\"${name}\" time=\"${duration}\"/>"
}

# Record a failing test case.
# Usage: junit_fail CLASSNAME NAME DURATION MESSAGE [BODY]
junit_fail() {
  local classname="$1" name="$2" duration="$3" message="$4" body="${5:-}"
  _JUNIT_TESTS=$((_JUNIT_TESTS + 1))
  _JUNIT_FAILURES=$((_JUNIT_FAILURES + 1))
  local esc_body
  esc_body="$(junit_xml_escape "$body")"
  _JUNIT_TC_XML="${_JUNIT_TC_XML}<testcase classname=\"${classname}\" name=\"${name}\" time=\"${duration}\"><failure message=\"${message}\">${esc_body}</failure></testcase>"
}

# Record a skipped test case.
# Usage: junit_skip CLASSNAME NAME MESSAGE
junit_skip() {
  local classname="$1" name="$2" message="$3"
  _JUNIT_TC_XML="${_JUNIT_TC_XML}<testcase classname=\"${classname}\" name=\"${name}\"><skipped message=\"${message}\"/></testcase>"
}

# Write the accumulated test suite to a JUnit XML file and print a summary.
# Usage: junit_write SUITE_NAME FILE_PATH
# Returns: exit code 1 if there were failures, 0 otherwise.
junit_write() {
  local suite_name="$1" file_path="$2"
  mkdir -p "$(dirname "$file_path")"
  cat >"$file_path" <<JEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="${suite_name}" tests="${_JUNIT_TESTS}" failures="${_JUNIT_FAILURES}">
${_JUNIT_TC_XML}
</testsuite>
JEOF
  echo "JUnit report: $file_path (${_JUNIT_TESTS} tests, ${_JUNIT_FAILURES} failures)"
  [ "$_JUNIT_FAILURES" -eq 0 ]
}
