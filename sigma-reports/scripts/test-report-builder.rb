#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'lib/report_builder'
require_relative 'lib/report_spec_validator'

class ReportBuilderTest < Minitest::Test
  SCAFFOLDER = File.join(__dir__, 'scaffold-report.rb')

  def scaffold(template)
    Dir.mktmpdir('report-scaffold') do |tmp|
      path = File.join(tmp, "#{template}.json")
      stdout, stderr, status = Open3.capture3(
        'ruby', SCAFFOLDER,
        '--template', template,
        '--name', "#{template} fixture",
        '--folder-id', 'folder-fixture',
        '--connection-id', 'connection-fixture',
        '--company', 'ACME',
        '--output', path
      )
      assert status.success?, "#{stdout}\n#{stderr}"
      return JSON.parse(File.read(path))
    end
  end

  def validate(spec)
    ReportSpec::Validator.new(spec, mode: :create).validate
  end

  def test_board_scaffold_is_a_valid_five_page_executive_report
    spec = scaffold('board')
    document = spec.fetch('document')
    visible_pages = document.fetch('pages').reject { |page| page['visibility'] == 'hidden' }
    result = validate(spec)

    assert_empty result.errors
    assert_equal 5, visible_pages.length
    assert_equal 1, document.fetch('pages').count { |page| page['visibility'] == 'hidden' }
    assert_equal %w[footer header], document.fetch('panels').map { |panel| panel['type'] }.sort
    assert document.fetch('elements').any? { |element| element['kind'] == 'waterfall-chart' }
    assert document.fetch('elements').any? { |element| element.dig('source', 'kind') == 'sql' }
    assert document.fetch('elements').any? { |element| element['kind'] == 'image' }
  end

  def test_wide_table_scaffold_uses_tabloid_pages_and_explicit_slices
    spec = scaffold('wide-table')
    document = spec.fetch('document')
    visible_pages = document.fetch('pages').reject { |page| page['visibility'] == 'hidden' }
    tables = document.fetch('elements').select do |element|
      element['kind'] == 'table' && element['id'].match?(/\Ap\d-table\z/)
    end
    result = validate(spec)

    assert_empty result.errors
    assert_equal({'pageWidth' => 1632, 'pageHeight' => 1056, 'margin' => 50}, document['config'])
    assert_equal 4, visible_pages.length
    assert_equal 4, tables.length
    assert tables.all? { |table| table.fetch('filters').length == 1 }
    assert tables.all? { |table| table.fetch('columns').length == 17 }
    assert_equal 16, document.fetch('elements').count { |element| element['id'].include?('-band-') }
  end

  def test_computed_row_rejects_geometry_overflow
    builder = ReportSpec::Builder.new(name: 'Geometry', folder_id: 'folder')

    error = assert_raises(ArgumentError) do
      builder.computed_row(widths: [500, 500], gap: 40, left: 0, right: 800)
    end
    assert_includes error.message, 'only 800'
  end

  def test_builder_rejects_duplicate_elements_and_regions
    builder = ReportSpec::Builder.new(name: 'Duplicates', folder_id: 'folder')
    builder.add_page(id: 'p1', name: 'Page')
    builder.place(
      builder.text(id: 'title', body: 'Title'),
      region: 'p1', x: 0, y: 0, width: 100, height: 30
    )

    assert_raises(ArgumentError) do
      builder.place(
        builder.text(id: 'title', body: 'Duplicate'),
        region: 'p1', x: 0, y: 40, width: 100, height: 30
      )
    end
    assert_raises(ArgumentError) { builder.add_page(id: 'p1', name: 'Duplicate') }
  end
end
