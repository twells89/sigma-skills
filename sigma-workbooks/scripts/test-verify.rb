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
# actually come back `valid: true` in whatever org runs this. `folderId` is
# resolved the same way, at runtime, via `/v2/whoami` (same idiom as
# tableau-to-sigma's probe-control-formula.rb) — never hardcode one org's
# real folder id here.
#
# Envelope (2026-08-04): /v2/workbooks/spec/verify now requires the request
# wrapped as { name, folderId, document: { schemaVersion, kind, pages,
# layout } } — see wb-rep.rb's wrap_for_verify comment for the full story.
# GOOD_SPEC/BAD_SPEC below are written in that wrapped shape directly (they
# exercise cmd_verify's already-wrapped passthrough branch). GOOD_SPEC_FLAT
# is deliberately the OLD flat shape — the shape every other command in
# this file (push/pull/import/assemble) still reads/writes on disk, and
# what `validate.md` §1 tells a human to hand `wb-rep.rb verify` — to pin
# that cmd_verify's auto-wrap-at-the-boundary keeps that documented usage
# working without the caller having to know about the envelope at all.

require 'json'
require 'net/http'
require 'uri'
require 'tempfile'
require 'open3'

$failures = 0
def check(desc)
  ok = yield
  puts(ok ? "[ok] #{desc}" : "[FAIL] #{desc}")
  $failures += 1 unless ok
end

unless ENV['SIGMA_BASE_URL'] && ENV['SIGMA_API_TOKEN']
  warn 'test-verify: SIGMA_BASE_URL / SIGMA_API_TOKEN not set — eval "$(get-token.sh)" first (sigma-api skill)'
  exit 2
end

def api_get(path)
  uri = URI.join(ENV.fetch('SIGMA_BASE_URL'), path)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{ENV.fetch('SIGMA_API_TOKEN')}"
  req['Accept'] = 'application/json'
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 30) { |h| h.request(req) }
  JSON.parse(res.body)
end

def home_folder_id
  me = (api_get('/v2/whoami') rescue nil)
  uid = me && (me['memberId'] || me['userId'] || me['id'])
  mem = uid ? (api_get("/v2/members/#{uid}") rescue nil) : nil
  [me, mem].compact.map { |h| h['homeFolderId'] || h['homeFolder'] }.compact.first
end

WB_REP = File.expand_path('wb-rep.rb', __dir__)
CONNECTION_ID = '362d859b-f432-4657-8e58-efc8535aa354' # Sigma Sample Database
TABLE_PATH = %w[RETAIL PLUGS_ELECTRONICS F_POINT_OF_SALE].freeze
FOLDER_ID = home_folder_id or abort('test-verify: could not resolve home folder id via /v2/whoami — is SIGMA_API_TOKEN valid?')

def table_element(total_sales_formula)
  { 'id' => 'tbl1', 'kind' => 'table', 'name' => 'Sales',
    'source' => { 'kind' => 'warehouse-table', 'connectionId' => CONNECTION_ID, 'path' => TABLE_PATH },
    'columns' => [
      { 'id' => 'c1', 'name' => 'Sales Amount', 'formula' => '[SALES_AMOUNT]' },
      { 'id' => 'c2', 'name' => 'Total Sales', 'formula' => total_sales_formula }
    ] }
end

# Wrapped shape — what actually goes over the wire to /v2/workbooks/spec/verify today.
def spec_with(total_sales_formula)
  {
    'name' => 'wb-rep verify test fixture',
    'folderId' => FOLDER_ID,
    'document' => {
      'schemaVersion' => 1,
      'kind' => 'workbook',
      'pages' => [{ 'id' => 'page1', 'name' => 'Page 1', 'elements' => [table_element(total_sales_formula)] }]
    }
  }
end

# Flat shape — what a human/agent actually has on disk per validate.md §1 and every other
# wb-rep.rb command (push/pull/import/assemble). Only used to prove cmd_verify's auto-wrap
# keeps that documented, unwrapped usage working.
def flat_spec_with(total_sales_formula)
  {
    'name' => 'wb-rep verify test fixture (flat)',
    'folderId' => FOLDER_ID,
    'schemaVersion' => 1,
    'pages' => [{ 'id' => 'page1', 'name' => 'Page 1', 'elements' => [table_element(total_sales_formula)] }]
  }
end

GOOD_SPEC = spec_with('Sum([SALES_AMOUNT])')
BAD_SPEC = spec_with('Sum([NoSuchTable/fake_col])')
GOOD_SPEC_FLAT = flat_spec_with('Sum([SALES_AMOUNT])')

def run_verify(spec)
  Tempfile.create(['wb-rep-verify-test', '.json']) do |f|
    f.write(JSON.generate(spec))
    f.flush
    out, status = Open3.capture2e('ruby', WB_REP, 'verify', f.path)
    return [out, status.exitstatus]
  end
end

out, code = run_verify(BAD_SPEC)
check('verify: bad column reference -> "valid: false" on stdout') { out.include?('valid: false') }
check('verify: bad column reference -> prints the error') { out =~ /fake_col|Dependency not found/i }
check('verify: bad column reference -> non-zero exit') { code != 0 }

out, code = run_verify(GOOD_SPEC)
check('verify: known-good spec (wrapped) -> "valid: true" on stdout') { out.include?('valid: true') }
check('verify: known-good spec (wrapped) -> zero exit') { code.zero? }

out, code = run_verify(GOOD_SPEC_FLAT)
check('verify: known-good spec (flat, on-disk shape) -> auto-wrapped -> "valid: true"') { out.include?('valid: true') }
check('verify: known-good spec (flat, on-disk shape) -> zero exit') { code.zero? }

exit($failures.zero? ? 0 : 1)
