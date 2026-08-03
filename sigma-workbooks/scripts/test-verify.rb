# frozen_string_literal: true
# test-verify.rb — integration test for `wb-rep.rb verify` (the
# POST /v2/workbooks/spec/verify dry-run subcommand).
#
# Run directly (from sigma-workbooks/):
#   eval "$(<sigma-api skill dir>/scripts/get-token.sh)"
#   ruby scripts/test-verify.rb
#
# Unlike scripts/lib/test_*.rb (pure-function unit tests, no network),
# this one necessarily hits the live API: `verify`'s entire job is a
# network call, so there's nothing to check without one. Requires
# SIGMA_BASE_URL / SIGMA_API_TOKEN (see wb-rep.rb's own header comment,
# or reference/workflows/crud.md).
#
# Fixtures point at RETAIL.PLUGS_ELECTRONICS.F_POINT_OF_SALE via the
# "Sigma Sample Database" connection in the org this test runs against —
# deliberately NOT the connectionId baked into
# reference/specification/example-full.yaml, which belongs to a different
# demo org and 404s as "Connection not found" everywhere else. A
# real, live-resolvable source is the point: it's what lets the bad-ref
# fixture below fail for the reason under test (an unresolved dependency)
# instead of an unrelated connection error, and lets the good fixture
# actually come back `valid: true` in whatever org runs this.

require 'json'
require 'tempfile'
require 'open3'

$failures = 0
def check(desc)
  ok = yield
  puts(ok ? "[ok] #{desc}" : "[FAIL] #{desc}")
  $failures += 1 unless ok
end

WB_REP = File.expand_path('wb-rep.rb', __dir__)
CONNECTION_ID = '362d859b-f432-4657-8e58-efc8535aa354' # Sigma Sample Database
TABLE_PATH = %w[RETAIL PLUGS_ELECTRONICS F_POINT_OF_SALE].freeze
FOLDER_ID = '57e59735-86b9-40b0-b029-217205406f57' # My Documents

def spec_with(total_sales_formula)
  {
    'name' => 'wb-rep verify test fixture',
    'folderId' => FOLDER_ID,
    'schemaVersion' => 1,
    'pages' => [
      { 'id' => 'page1', 'name' => 'Page 1', 'elements' => [
        { 'id' => 'tbl1', 'kind' => 'table', 'name' => 'Sales',
          'source' => { 'kind' => 'warehouse-table', 'connectionId' => CONNECTION_ID, 'path' => TABLE_PATH },
          'columns' => [
            { 'id' => 'c1', 'name' => 'Sales Amount', 'formula' => '[SALES_AMOUNT]' },
            { 'id' => 'c2', 'name' => 'Total Sales', 'formula' => total_sales_formula }
          ] }
      ] }
    ]
  }
end

GOOD_SPEC = spec_with('Sum([SALES_AMOUNT])')
BAD_SPEC = spec_with('Sum([NoSuchTable/fake_col])')

def run_verify(spec)
  Tempfile.create(['wb-rep-verify-test', '.json']) do |f|
    f.write(JSON.generate(spec))
    f.flush
    out, status = Open3.capture2e('ruby', WB_REP, 'verify', f.path)
    return [out, status.exitstatus]
  end
end

unless ENV['SIGMA_BASE_URL'] && ENV['SIGMA_API_TOKEN']
  warn 'test-verify: SIGMA_BASE_URL / SIGMA_API_TOKEN not set — eval "$(get-token.sh)" first (sigma-api skill)'
  exit 2
end

out, code = run_verify(BAD_SPEC)
check('verify: bad column reference -> "valid: false" on stdout') { out.include?('valid: false') }
check('verify: bad column reference -> prints the error') { out =~ /fake_col|Dependency not found/i }
check('verify: bad column reference -> non-zero exit') { code != 0 }

out, code = run_verify(GOOD_SPEC)
check('verify: known-good spec -> "valid: true" on stdout') { out.include?('valid: true') }
check('verify: known-good spec -> zero exit') { code.zero? }

exit($failures.zero? ? 0 : 1)
