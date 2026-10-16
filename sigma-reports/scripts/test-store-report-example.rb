#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'lib/report_spec_validator'

class StoreReportExampleTest < Minitest::Test
  EXAMPLE = File.expand_path('../examples/store-operating-report', __dir__)

  def build
    Dir.mktmpdir('store-report') do |tmp|
      path = File.join(tmp, 'report.json')
      stdout, stderr, status = Open3.capture3(
        'ruby', File.join(EXAMPLE, 'build.rb'),
        '--folder-id', 'folder-fixture', '--connection-id', 'connection-fixture', '--output', path
      )
      assert status.success?, "#{stdout}\n#{stderr}"
      return JSON.parse(File.read(path))
    end
  end

  def elements(spec)
    spec.dig('document', 'elements').to_h { |element| [element['id'], element] }
  end

  def test_example_is_a_valid_two_page_report_with_a_hidden_data_page
    spec = build
    result = ReportSpec::Validator.new(spec, mode: :create).validate
    assert_empty result.errors
    assert_empty result.warnings

    pages = spec.dig('document', 'pages')
    assert_equal %w[page-1 page-2], pages.reject { |page| page['visibility'] == 'hidden' }.map { |page| page['id'] }
    assert_equal 'hidden', pages.find { |page| page['id'] == 'data' }['visibility']
  end

  def test_store_control_filters_every_sql_source_except_its_value_list
    by_id = elements(build)
    control = by_id.fetch('ctl-store-el')
    assert_equal 'list', control['controlType']
    assert_equal 'single', control['selectionMode']
    assert_equal 'src-stores', control.dig('source', 'source', 'elementId')

    sql_sources = by_id.values.select { |element| element.dig('source', 'kind') == 'sql' }.map { |element| element['id'] }
    targets = control['filters'].map { |filter| filter.dig('source', 'elementId') }
    assert_equal (sql_sources - ['src-stores']).sort, targets.sort

    control['filters'].each do |filter|
      source = by_id.fetch(filter.dig('source', 'elementId'))
      column = source['columns'].find { |candidate| candidate['id'] == filter['columnId'] }
      assert column, "#{filter['columnId']} is not a column of #{source['id']}"
      assert_equal 'store_id', column['name']
    end
  end

  def test_each_visible_page_has_its_own_numbered_footer
    spec = build
    footers = spec.dig('document', 'panels').select { |panel| panel['type'] == 'footer' }
    assert_equal [%w[page-1], %w[page-2]], footers.map { |panel| panel['pages'] }
    bodies = elements(spec)
    assert_includes bodies.fetch('ftr-1-page')['body'], 'Page 1 of 2'
    assert_includes bodies.fetch('ftr-2-page')['body'], 'Page 2 of 2'
  end

  def test_refunds_and_headline_sql_are_consistent_and_null_safe
    require_relative '../examples/store-operating-report/sql'
    assert_includes STORE_CTES, "ORDER_STATUS = 'refunded', COALESCE(REFUND_AMOUNT_USD, 0)"
    assert_includes EXCEPTIONS_SQL, "o.ORDER_STATUS = 'refunded'"
    headline = SUMMARY_SQL[/'Net sales of '.*?AS "headline"/m]
    assert headline, 'headline expression not found'
    refute_match(/NULLIF|\.(pm|ly)_net\b/, headline, 'optional clauses must be built in the h CTE, not inline')
    assert_includes headline, "COALESCE(s.ticket_clause || ', and the store ranked #', '. The store ranked #')"
  end

  def test_scorecard_deltas_are_colored_by_direction_aware_signals
    scorecard = elements(build).fetch('p1-scorecard')
    formulas = scorecard['conditionalFormats'].map { |rule| [rule['condition'], rule['formula']] }
    assert_includes formulas, ['formula', '[pm_signal] > 0']
    assert_includes formulas, ['formula', '[ly_signal] < 0']
  end

  def test_burst_drafter_routes_to_the_test_inbox_and_refuses_without_one
    Dir.mktmpdir('burst') do |tmp|
      csv = File.join(tmp, 'recipients.csv')
      CSV.open(csv, 'w') do |out|
        out << %w[store_id store_name recipient_email recipient_type]
        out << ['ST001', 'New York Main', 'manager@example.com', 'store manager']
        out << ['ST015', 'Charlotte Commons', 'st015@example.com', 'store inbox']
      end
      script = File.join(EXAMPLE, 'draft-burst-schedules.rb')

      _out, _err, refused = Open3.capture3('ruby', script, '--recipients', csv)
      refute refused.success?, 'drafter must refuse without --test-email or --live'

      duplicated = File.join(tmp, 'duplicated.csv')
      File.write(duplicated, File.read(csv) + "ST001,New York Main,other@example.com,store manager\n")
      _out, err, dup_status = Open3.capture3('ruby', script, '--recipients', duplicated,
                                             '--test-email', 'review@example.com', '--output', File.join(tmp, 'dup.json'))
      refute dup_status.success?, 'drafter must refuse a CSV that repeats a store'
      assert_includes err, 'duplicate store_id rows: ST001'

      path = File.join(tmp, 'schedules.json')
      stdout, stderr, status = Open3.capture3('ruby', script, '--recipients', csv,
                                              '--test-email', 'review@example.com', '--output', path)
      assert status.success?, "#{stdout}\n#{stderr}"
      bodies = JSON.parse(File.read(path))
      assert_equal 2, bodies.size
      assert(bodies.all? { |body| body['target'] == [{ 'email' => 'review@example.com' }] })
      assert_equal({ 'type' => 'text', 'value' => 'ST015' }, bodies[1].dig('configV2', 'controlValues', 'store'))
      assert_includes bodies[1].dig('configV2', 'messageBody'), 'intended for st015@example.com'
    end
  end
end
