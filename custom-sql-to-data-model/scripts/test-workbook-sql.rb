#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/workbook_sql'
require_relative 'lib/formula_audit'

response = {
  'workbookId' => 'wb-1',
  'folderId' => 'folder-1',
  'document' => {
    'schemaVersion' => 1,
    'kind' => 'workbook',
    'pages' => [{ 'id' => 'page-1', 'name' => 'Main' }],
    'elements' => [
      {
        'id' => 'sql-1',
        'kind' => 'table',
        'name' => '',
        'source' => {
          'kind' => 'sql',
          'connectionId' => 'connection-1',
          'statement' => 'select {{RegionControl}} as region'
        },
        'columns' => [{ 'id' => 'region', 'formula' => '[Custom SQL/region]' }]
      },
      {
        'id' => 'warehouse-1',
        'kind' => 'table',
        'source' => { 'kind' => 'warehouse-table', 'connectionId' => 'connection-1' }
      }
    ],
    'layout' => '<Page id="page-1"><LayoutElement elementId="sql-1"/>' \
                '<LayoutElement elementId="warehouse-1"/></Page>'
  }
}

findings = Sigma::WorkbookSql.findings(
  response, workbook_id: 'wb-1', workbook_name: 'Orders'
)
abort "expected one SQL finding, got #{findings.inspect}" unless findings.length == 1

finding = findings.first
expected = {
  workbook_id: 'wb-1',
  workbook_name: 'Orders',
  folder_id: 'folder-1',
  element_id: 'sql-1',
  element_name: 'Orders SQL',
  connection_id: 'connection-1',
  sql: 'select {{RegionControl}} as region',
  column_count: 1
}
abort "unexpected finding: #{finding.inspect}" unless finding == expected
abort 'scanner must not re-nest elements under pages' if response.dig('document', 'pages', 0).key?('elements')

audit_doc = {
  'elements' => [
    {
      'id' => 'swapped',
      'source' => { 'kind' => 'data-model' },
      'columns' => [
        { 'id' => 'OT_HOURS', 'name' => 'OT Hours', 'formula' => '[OT Summary/OT_HOURS]' }
      ]
    },
    {
      'id' => 'warehouse',
      'source' => { 'kind' => 'warehouse-table' },
      'columns' => [
        {
          'id' => 'TRANSACTION_TYPE',
          'name' => 'Transaction Type',
          'formula' => '[F_SALES/TRANSACTION_TYPE]'
        }
      ]
    }
  ]
}
fixed = Sigma::FormulaAudit.repair!(audit_doc)
abort "expected one post-swap repair, got #{fixed}" unless fixed == 1
abort 'post-swap formula was not repaired' unless audit_doc.dig(
  'elements', 0, 'columns', 0, 'formula'
) == '[OT Summary/OT Hours]'
abort 'raw warehouse formula must remain unchanged' unless audit_doc.dig(
  'elements', 1, 'columns', 0, 'formula'
) == '[F_SALES/TRANSACTION_TYPE]'

puts 'PASS — flat SQL scan, control refs, post-swap repair, and raw names'
