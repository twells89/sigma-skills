# frozen_string_literal: true
# test_code_rep.rb — run directly: ruby scripts/lib/test_code_rep.rb (from sigma-workbooks/)
#
# Pure-function unit test (no network) for Sigma::CodeRep, the adapter every
# workbook-spec read/write path in wb-rep.rb (and custom-sql-to-data-model's
# scan-workbooks.rb/audit-formulas.rb) now routes through to handle the
# document-wrapper wire change. See lib/code_rep.rb's header comment for the
# full story and reference/workflows/validate.md §1 for the live-verified
# request/response shapes this pins against.
require_relative 'code_rep'

$f = 0
def check(d)
  ok = yield
  puts(ok ? "[ok] #{d}" : "[FAIL] #{d}")
  $f += 1 unless ok
end

NESTED_RESPONSE = {
  'name' => 'Demo', 'folderId' => 'fld1', 'workbookId' => 'wb1', 'url' => 'https://x/wb1',
  'document' => {
    'schemaVersion' => 1, 'kind' => 'workbook',
    'pages' => [{ 'id' => 'p1', 'name' => 'Page 1', 'elements' => [] }],
    'layout' => '<Layout/>'
  }
}.freeze

FLAT_SPEC = {
  'name' => 'Demo', 'folderId' => 'fld1',
  'schemaVersion' => 1, 'pages' => [{ 'id' => 'p1', 'name' => 'Page 1', 'elements' => [] }],
  'layout' => '<Layout/>'
}.freeze

# --- document() : unwrap a live (nested) GET response back to the flat
# shape every other function in this codebase reads (spec['pages'], etc). ---

check('document() unwraps a nested API response to a flat hash') do
  flat = Sigma::CodeRep.document(NESTED_RESPONSE)
  flat['pages'] == NESTED_RESPONSE['document']['pages'] &&
    flat['schemaVersion'] == 1 &&
    flat['layout'] == '<Layout/>' &&
    flat['name'] == 'Demo' && # metadata survives alongside the unwrapped document fields
    !flat.key?('document')
end

check('document() is a no-op on an already-flat spec (on-disk shape)') do
  Sigma::CodeRep.document(FLAT_SPEC) == FLAT_SPEC
end

check('document() tolerates a non-Hash input without raising') do
  Sigma::CodeRep.document(nil) == {} && Sigma::CodeRep.document('oops') == {}
end

# --- metadata() : the non-document (name/folderId/...) fields, from either shape. ---

check('metadata() strips document fields from a flat spec') do
  Sigma::CodeRep.metadata(FLAT_SPEC) == { 'name' => 'Demo', 'folderId' => 'fld1' }
end

check('metadata() strips document fields from a nested response, plus response-only fields') do
  m = Sigma::CodeRep.metadata(NESTED_RESPONSE)
  m['name'] == 'Demo' && m['folderId'] == 'fld1' && m['workbookId'] == 'wb1' && !m.key?('pages')
end

# --- wrap() : build the wire body a live POST/PUT/verify now requires. ---

check('wrap() nests document fields under "document" and merges extra at top level (POST/verify shape)') do
  wire = Sigma::CodeRep.wrap(FLAT_SPEC, extra: Sigma::CodeRep.metadata(FLAT_SPEC))
  wire == {
    'name' => 'Demo', 'folderId' => 'fld1',
    'document' => { 'schemaVersion' => 1, 'kind' => 'workbook',
                     'pages' => FLAT_SPEC['pages'], 'layout' => '<Layout/>' }
  }
end

check('wrap() with no extra sends just {document: {...}} (PUT/update shape)') do
  Sigma::CodeRep.wrap(FLAT_SPEC) == {
    'document' => { 'schemaVersion' => 1, 'kind' => 'workbook',
                     'pages' => FLAT_SPEC['pages'], 'layout' => '<Layout/>' }
  }
end

check('wrap() defaults kind to "workbook" when the on-disk spec omits it') do
  Sigma::CodeRep.wrap(FLAT_SPEC).dig('document', 'kind') == 'workbook'
end

check('wrap() is idempotent on an already-wrapped spec (same wire shape either way)') do
  already_wrapped = { 'name' => 'Demo', 'folderId' => 'fld1', 'document' => FLAT_SPEC.slice('schemaVersion', 'pages', 'layout').merge('kind' => 'workbook') }
  Sigma::CodeRep.wrap(FLAT_SPEC, extra: { 'name' => 'Demo', 'folderId' => 'fld1' }) ==
    Sigma::CodeRep.wrap(already_wrapped, extra: { 'name' => 'Demo', 'folderId' => 'fld1' })
end

check('round trip: wrap(document(live nested response)) reproduces the original document payload') do
  roundtripped = Sigma::CodeRep.wrap(Sigma::CodeRep.document(NESTED_RESPONSE))
  roundtripped['document'] == NESTED_RESPONSE['document']
end

exit($f.zero? ? 0 : 1)
