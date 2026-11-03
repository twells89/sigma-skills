#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline unit test for the endpoint helpers in lib/code_rep.rb. The workbook
# /spec endpoints are deprecated (OpenAPI 2.0.0+20261030); the replacements
# carry the same document under `contents`.
#   ruby scripts/test-code-rep.rb

require 'minitest/autorun'
require_relative 'lib/code_rep'
require_relative 'lib/workbook_sql'

class CodeRepEndpointTest < Minitest::Test
  DOCUMENT = {
    'schemaVersion' => 1, 'kind' => 'workbook',
    'pages' => [{ 'id' => 'p1', 'name' => 'Main' }],
    'elements' => [{
      'id' => 'sql-1', 'kind' => 'table', 'name' => 'Q',
      'source' => { 'kind' => 'sql', 'connectionId' => 'c1', 'statement' => 'select 1' }
    }],
    'layout' => '<Page id="p1"><Element elementId="sql-1"/></Page>'
  }.freeze

  ARTIFACT = { 'name' => 'WB', 'folderId' => 'f1', 'document' => DOCUMENT }.freeze

  def test_paths
    assert_equal '/v2/workbooks', Sigma::CodeRep.create_path
    assert_equal '/v2/workbooks/w1?includeContents=true', Sigma::CodeRep.read_path('w1')
    assert_equal '/v2/workbooks/w1?includeContents=true&documentVersion=3',
                 Sigma::CodeRep.read_path('w1', document_version: 3)
    assert_equal '/v2/workbooks/w1/contents', Sigma::CodeRep.update_path('w1')
    assert_equal '/v2/reports', Sigma::CodeRep.create_path(:report)
    assert_equal '/v2/reports/r1?includeContents=true', Sigma::CodeRep.read_path('r1', :report)
    assert_equal '/v2/reports/r1/contents', Sigma::CodeRep.update_path('r1', :report)
    assert_raises(ArgumentError) { Sigma::CodeRep.create_path(:dataModel) }
  end

  def test_reads_live_contents_shape
    live = { 'workbookId' => 'w1', 'name' => 'WB', 'path' => 'My Documents', 'latestVersion' => 2,
             'documentVersion' => 2, 'contents' => DOCUMENT }
    assert_equal Sigma::CodeRep.document(ARTIFACT), Sigma::CodeRep.document(live)
    refute_includes Sigma::CodeRep.metadata(live).keys, 'contents'
    refute_includes Sigma::CodeRep.strip_response_only(live).keys, 'path'
  end

  def test_workbook_sql_scanner_reads_contents_shape
    live = { 'workbookId' => 'w1', 'name' => 'WB', 'contents' => DOCUMENT }
    findings = Sigma::WorkbookSql.findings(live, workbook_id: 'w1', workbook_name: 'WB')
    assert_equal ['sql-1'], findings.map { |f| f[:element_id] }
    assert_nil findings.first[:folder_id] # the new GET does not return folderId
  end

  def test_create_and_update_bodies_rekey_document_to_contents
    body = Sigma::CodeRep.create_body(ARTIFACT)
    assert_equal %w[contents folderId name], body.keys.sort
    refute body.key?('document')
    assert_equal true, Sigma::CodeRep.create_body(ARTIFACT, dry_run: true)['dryRun']
    assert_equal ['contents'], Sigma::CodeRep.update_body(ARTIFACT).keys
    assert_equal 4, Sigma::CodeRep.update_body(ARTIFACT, document_version: 4)['documentVersion']
  end

  def test_create_body_flattens_legacy_page_nested_elements
    legacy = { 'schemaVersion' => 1, 'pages' => [{ 'id' => 'p', 'elements' => [{ 'id' => 'old' }] }] }
    body = Sigma::CodeRep.create_body(legacy, extra: { 'name' => 'N', 'folderId' => 'f' })
    assert_equal ['old'], body['contents']['elements'].map { |e| e['id'] }
    assert(body['contents']['pages'].none? { |pg| pg.key?('elements') })
  end

  def test_dry_run_result_normalizes_live_shapes
    assert_equal true, Sigma::CodeRep.dry_run_result(200, { 'dryRun' => true, 'warnings' => [] })['valid']
    bad = Sigma::CodeRep.dry_run_result(400, { 'valid' => false, 'errors' => [{ 'summary' => 'contents.x: bad' }] })
    assert_equal false, bad['valid']
    assert_equal ['contents.x: bad'], bad['errors'].map { |e| e['summary'] }
    assert_equal [{ 'summary' => 'nope' }], Sigma::CodeRep.dry_run_result(403, { 'message' => 'nope' })['errors']
  end

  def test_strip_response_only_covers_both_eras
    rb = { 'workbookId' => 'w', 'workbookUrlId' => 'u', 'path' => 'p', 'latestVersion' => 1,
           'latestDocumentVersion' => 1, 'folderId' => 'f', 'name' => 'N', 'contents' => {} }
    assert_equal %w[contents folderId name], Sigma::CodeRep.strip_response_only(rb).keys.sort
  end
end
