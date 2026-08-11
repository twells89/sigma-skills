#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require_relative 'lib/report_spec_validator'

class ReportSpecValidatorTest < Minitest::Test
  def valid_payload
    {
      'name' => 'Statement',
      'folderId' => 'folder-1',
      'document' => {
        'schemaVersion' => 1,
        'kind' => 'report',
        'config' => {'pageWidth' => 800, 'pageHeight' => 1_000, 'margin' => 40},
        'elements' => [
          {'id' => 'title', 'kind' => 'text', 'body' => 'Title'},
          {'id' => 'footer-text', 'kind' => 'text', 'body' => 'Footer'}
        ],
        'pages' => [{'id' => 'page-1', 'name' => 'Page 1'}],
        'panels' => [
          {
            'id' => 'footer', 'type' => 'footer', 'pages' => ['page-1'],
            'config' => {'height' => 40}
          }
        ],
        'layout' => <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <Page id="page-1">
            <Element elementId="title" x="40" y="40" width="720" height="80"/>
          </Page>
          <Panel id="footer" type="footer">
            <Element elementId="footer-text" x="40" y="8" width="720" height="24"/>
          </Panel>
        XML
      }
    }
  end

  def validate(payload = valid_payload, mode: :create)
    ReportSpec::Validator.new(payload, mode: mode).validate
  end

  def test_accepts_valid_create_representation
    result = validate
    assert_empty result.errors
    assert_empty result.warnings
  end

  def test_update_accepts_only_document_wrapper
    payload = {'document' => valid_payload.fetch('document'), 'name' => 'Not allowed'}
    result = validate(payload, mode: :update)
    assert_includes result.errors, 'update body must contain exactly one property: document'
  end

  def test_rejects_unsupported_and_workbook_only_elements
    payload = valid_payload
    payload['document']['elements'][0]['kind'] = 'waterfall-chart'
    payload['document']['elements'][1]['kind'] = 'container'
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('waterfall-chart is unsupported') }
    assert result.errors.any? { |error| error.include?('container is workbook-only') }
  end

  def test_warns_for_schema_only_element
    payload = valid_payload
    payload['document']['elements'][0]['kind'] = 'plugin'
    result = validate(payload)
    assert result.warnings.any? { |warning| warning.include?('plugin is schema-only') }
  end

  def test_rejects_grid_layout_duplicate_placement_and_bounds
    payload = valid_payload
    payload['document']['layout'] = <<~XML
      <Page id="page-1">
        <Element elementId="title" x="40" y="40" width="900" height="80" gridColumn="1 / 25"/>
        <Element elementId="title" x="40" y="140" width="720" height="80"/>
      </Page>
      <Panel id="footer" type="footer">
        <Element elementId="footer-text" x="40" y="8" width="720" height="40"/>
      </Panel>
    XML
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('forbidden workbook attribute gridColumn') }
    assert result.errors.any? { |error| error.include?('placed more than once') }
    assert result.errors.any? { |error| error.include?('exceeds page width') }
    assert result.errors.any? { |error| error.include?('exceeds panel height') }
  end

  def test_rejects_panel_assignment_and_layout_type_mismatch
    payload = valid_payload
    payload['document']['panels'][0]['pages'] = ['missing-page']
    payload['document']['layout'] = payload['document']['layout'].sub('type="footer"', 'type="header"')
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('references unknown page') }
    assert result.errors.any? { |error| error.include?('does not match metadata type') }
  end

  def test_rejects_missing_and_undeclared_layout_objects
    payload = valid_payload
    payload['document']['layout'] = <<~XML
      <Page id="other-page">
        <Element elementId="unknown" x="0" y="0" width="10" height="10"/>
      </Page>
    XML
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('undeclared page id') }
    assert result.errors.any? { |error| error.include?('references undeclared elementId') }
    assert result.errors.any? { |error| error.include?('page is missing from layout') }
    assert result.errors.any? { |error| error.include?('panel is missing from layout') }
  end

  def test_rejects_invalid_xml_and_doctype
    payload = valid_payload
    payload['document']['layout'] = '<Page id="page-1"><Element></Page>'
    assert validate(payload).errors.any? { |error| error.include?('invalid XML') }

    payload['document']['layout'] = '<!DOCTYPE Page><Page id="page-1"/>'
    assert validate(payload).errors.any? { |error| error.include?('DOCTYPE') }
  end

  def test_minimal_example_uses_current_text_element_shape
    example_path = File.expand_path('../reference/specification/example-minimal.json', __dir__)
    example = JSON.parse(File.read(example_path))
    text_elements = example.dig('document', 'elements').select { |element| element['kind'] == 'text' }

    assert text_elements.all? { |element| element.key?('body') }
    refute text_elements.any? { |element| element.key?('text') || element.key?('name') }
    assert ReportSpec::Validator.new(example, mode: :create).validate.valid?
  end
end
