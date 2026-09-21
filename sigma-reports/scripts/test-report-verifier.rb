#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'lib/report_verifier'

class ReportVerifierTest < Minitest::Test
  def test_clean_sql_has_no_markers
    sql = 'SELECT region, SUM(revenue) FROM sales GROUP BY region'
    assert_empty ReportSpec::Verifier.compile_markers(sql)
  end

  def test_extracts_unknown_and_circular_column_markers
    text = <<~TEXT
      SELECT 'Unknown column "[Revenue]"' AS value;
      Circular column reference to [Margin]
    TEXT
    markers = ReportSpec::Verifier.compile_markers(text)

    assert_includes markers, 'Unknown column "[Revenue]"'
    assert_includes markers, 'Circular column reference to [Margin]'
  end

  def test_extracts_dependency_failures_without_duplicates
    text = "Dependency not found: 'source-table'; Dependency not found: 'source-table'"
    markers = ReportSpec::Verifier.compile_markers(text)

    assert_equal 1, markers.length
    assert_match(/Dependency not found/i, markers.first)
  end
end
