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

  def test_update_accepts_optional_document_version_and_rejects_other_metadata
    payload = {'document' => valid_payload.fetch('document'), 'documentVersion' => 7}
    assert_empty validate(payload, mode: :update).errors

    payload['name'] = 'Not allowed'
    result = validate(payload, mode: :update)
    assert result.errors.any? { |error| error.include?('unsupported properties: name') }

    payload.delete('name')
    payload['documentVersion'] = '7'
    result = validate(payload, mode: :update)
    assert_includes result.errors, 'update documentVersion must be a finite number'
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

  def test_classifies_new_common_and_workbook_only_kinds
    payload = valid_payload
    payload['document']['elements'][0]['kind'] = 'treemap-chart'
    payload['document']['elements'][1]['kind'] = 'single-row-container'
    result = validate(payload)

    assert result.warnings.any? { |warning| warning.include?('treemap-chart is schema-only') }
    assert result.errors.any? { |error| error.include?('single-row-container is workbook-only') }
  end

  def test_warns_for_file_upload_control
    payload = valid_payload
    payload['document']['elements'][0].merge!(
      'kind' => 'control', 'controlType' => 'file-upload'
    )
    result = validate(payload)

    assert result.warnings.any? { |warning| warning.include?('schema-only file-upload controlType') }
  end

  def test_accepts_current_alignment_values_and_rejects_removed_values
    payload = valid_payload
    payload['document']['elements'][0]['verticalAlign'] = 'center'
    payload['document']['elements'][1].merge!(
      'kind' => 'divider', 'direction' => 'vertical', 'align' => 'left'
    )
    assert_empty validate(payload).errors

    payload['document']['elements'][0]['verticalAlign'] = 'middle'
    payload['document']['elements'][1].merge!(
      'kind' => 'kpi-chart', 'layout' => {'anchor' => 'middle', 'verticalAnchor' => 'end'}
    )
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('verticalAlign must be top, center, or bottom') }
    assert result.errors.any? { |error| error.include?('layout.anchor must be left, center, or right') }
    assert result.errors.any? { |error| error.include?('layout.verticalAnchor must be top, center, or bottom') }
  end

  def test_rejects_removed_id_pointer_on_maps_and_pivot_shelves
    payload = valid_payload
    payload['document']['elements'][0].merge!(
      'kind' => 'geography-map', 'geography' => {'id' => 'geo-column'}
    )
    payload['document']['elements'][1].merge!(
      'kind' => 'pivot-table', 'rowsBy' => [{'id' => 'row-column'}]
    )
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('geography uses removed id; use columnId') }
    assert result.errors.any? { |error| error.include?('rowsBy[0] uses removed id; use columnId') }

    payload['document']['elements'][0]['geography'] = {'columnId' => 'geo-column'}
    payload['document']['elements'][1]['rowsBy'] = [{'columnId' => 'row-column'}]
    assert_empty validate(payload).errors
  end

  def test_rejects_map_shaped_series_styles_and_color_overrides
    payload = valid_payload
    payload['document']['elements'][0]['seriesLineAreaStyle'] = {
      'value-column' => {'interpolation' => 'monotone'}
    }
    payload['document']['settings'] = {
      'theme' => {'overrides' => {'colorOverrides' => {'backgroundCanvas' => '#FFFFFF'}}}
    }
    result = validate(payload)
    assert result.errors.any? { |error| error.include?('seriesLineAreaStyle must be a list') }
    assert result.errors.any? { |error| error.include?('colorOverrides must be a list') }

    payload['document']['elements'][0]['seriesLineAreaStyle'] = [
      {'columnId' => 'value-column', 'style' => {'interpolation' => 'monotone'}}
    ]
    payload['document']['settings']['theme']['overrides']['colorOverrides'] = [
      {'name' => 'backgroundCanvas', 'color' => '#FFFFFF'}
    ]
    assert_empty validate(payload).errors
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
