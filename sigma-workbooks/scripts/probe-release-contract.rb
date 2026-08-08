#!/usr/bin/env ruby
# frozen_string_literal: true

# Live workbook-as-code release probe. Creates one temporary workbook, validates
# readback and compiled SQL, and always deletes it.
#
# Required: SIGMA_BASE_URL, SIGMA_API_TOKEN
# Optional: SIGMA_PROBE_CONNECTION_ID, SIGMA_PROBE_TABLE_PATH (comma-separated)

require 'json'
require 'net/http'
require 'time'
require 'uri'

BASE_URL = ENV.fetch('SIGMA_BASE_URL').sub(%r{/$}, '')
TOKEN = ENV.fetch('SIGMA_API_TOKEN')
CONNECTION_ID = ENV.fetch(
  'SIGMA_PROBE_CONNECTION_ID',
  '362d859b-f432-4657-8e58-efc8535aa354'
)
TABLE_PATH = ENV.fetch(
  'SIGMA_PROBE_TABLE_PATH',
  'RETAIL,PLUGS_ELECTRONICS,F_POINT_OF_SALE'
).split(',').map(&:strip).freeze

def request(method, path, body = nil, accept: 'application/json')
  uri = URI("#{BASE_URL}#{path}")
  klass = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post,
    delete: Net::HTTP::Delete
  }.fetch(method)
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Accept'] = accept
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body)
  end
  Net::HTTP.start(
    uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 120
  ) { |http| http.request(req) }
end

def json_request(method, path, body = nil)
  response = request(method, path, body)
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  [response.code.to_i, parsed]
rescue JSON::ParserError
  [response.code.to_i, { 'raw' => response.body }]
end

def home_folder_id
  code, whoami = json_request(:get, '/v2/whoami')
  raise "GET /v2/whoami -> #{code}: #{whoami}" unless code.between?(200, 299)

  member_id = whoami['memberId'] || whoami['userId'] || whoami['id']
  return whoami['homeFolderId'] || whoami['homeFolder'] if !member_id

  member_code, member = json_request(:get, "/v2/members/#{member_id}")
  candidates = [whoami]
  candidates << member if member_code.between?(200, 299)
  candidates.filter_map { |entry| entry['homeFolderId'] || entry['homeFolder'] }.first
end

def layout
  <<~XML
    <?xml version="1.0" encoding="utf-8"?>
    <Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="page-main">
      <LayoutElement elementId="probe-number" gridColumn="1 / 7" gridRow="1 / 4"/>
      <LayoutElement elementId="warehouse-table" gridColumn="1 / 13" gridRow="4 / 14"/>
      <LayoutElement elementId="sql-table" gridColumn="13 / 25" gridRow="4 / 14"/>
      <GridContainer elementId="header-container" type="grid" gridColumn="7 / 25" gridRow="1 / 4" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
        <LayoutElement elementId="dynamic-text" gridColumn="1 / 25" gridRow="1 / 4"/>
      </GridContainer>
      <GridContainer elementId="sales-repeater" type="grid" gridColumn="1 / 13" gridRow="14 / 24" gridTemplateColumns="repeat(12, 1fr)" gridTemplateRows="auto">
        <LayoutElement elementId="repeater-text" gridColumn="1 / 13" gridRow="1 / 4"/>
      </GridContainer>
      <TabbedContainer elementId="details-tabs" type="tabbed-container" gridColumn="13 / 25" gridRow="14 / 24">
        <Tab gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
          <LayoutElement elementId="tab-summary" gridColumn="1 / 25" gridRow="1 / 5"/>
        </Tab>
        <Tab gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
          <LayoutElement elementId="tab-detail" gridColumn="1 / 25" gridRow="1 / 5"/>
        </Tab>
      </TabbedContainer>
      <LayoutElement elementId="page-nav" gridColumn="1 / 13" gridRow="24 / 28"/>
      <LayoutElement elementId="progress-ring" gridColumn="13 / 25" gridRow="24 / 30"/>
      <LayoutElement elementId="print-break" gridColumn="1 / 25" gridRow="30 / 31"/>
    </Page>
  XML
end

def elements
  [
    {
      'id' => 'probe-number', 'kind' => 'control', 'controlId' => 'ProbeNumber',
      'controlType' => 'number', 'name' => 'Probe number', 'mode' => '=',
      'value' => 7
    },
    {
      'id' => 'warehouse-table', 'kind' => 'table', 'name' => 'Sales Source',
      'source' => {
        'kind' => 'warehouse-table', 'connectionId' => CONNECTION_ID,
        'path' => TABLE_PATH
      },
      'columns' => [
        {
          'id' => 'raw-sales-amount', 'name' => 'Sales Amount',
          'formula' => '[SALES_AMOUNT]'
        }
      ]
    },
    {
      'id' => 'sql-table', 'kind' => 'table', 'name' => 'Control SQL',
      'source' => {
        'kind' => 'sql', 'connectionId' => CONNECTION_ID,
        'statement' => 'SELECT {{ProbeNumber}} AS CONTROL_VALUE'
      },
      'columns' => [
        {
          'id' => 'control-value', 'name' => 'Control Value',
          'formula' => '[Custom SQL/CONTROL_VALUE]'
        }
      ]
    },
    {
      'id' => 'header-container', 'kind' => 'container',
      'style' => { 'backgroundColor' => '#EEF2F7', 'padding' => 'small' },
      'elementGap' => 'shown', 'spacing' => 'small'
    },
    {
      'id' => 'dynamic-text', 'kind' => 'text',
      'body' => 'Control value: {{[ProbeNumber]}}'
    },
    {
      'id' => 'sales-repeater', 'kind' => 'repeated-container',
      'source' => { 'kind' => 'table', 'elementId' => 'warehouse-table' },
      'arrangement' => 'list', 'cardSize' => 'small'
    },
    {
      'id' => 'repeater-text', 'kind' => 'text',
      'body' => '{{[Sales Source repeated container/Sales Amount]}}'
    },
    {
      'id' => 'details-tabs', 'kind' => 'tabbed-container',
      'tabs' => [{ 'name' => 'Summary' }, { 'name' => 'Detail' }],
      'tabBar' => { 'alignment' => 'start' }
    },
    { 'id' => 'tab-summary', 'kind' => 'text', 'body' => 'Summary tab' },
    { 'id' => 'tab-detail', 'kind' => 'text', 'body' => 'Detail tab' },
    {
      'id' => 'page-nav', 'kind' => 'navigation', 'mode' => 'manual',
      'options' => [
        {
          'label' => 'Main',
          'destination' => { 'type' => 'page', 'pageId' => 'page-main' }
        }
      ]
    },
    {
      'id' => 'progress-ring', 'kind' => 'progress', 'mode' => 'value',
      'min' => '0', 'max' => '10', 'value' => '7', 'shape' => 'ring'
    },
    { 'id' => 'print-break', 'kind' => 'page-break' }
  ]
end

def create_spec(folder_id, probe_elements: elements, probe_layout: layout)
  {
    'name' => "WAC release probe #{Time.now.utc.iso8601}",
    'folderId' => folder_id,
    'description' => 'Temporary workbook; created and deleted by probe-release-contract.rb',
    'document' => {
      'schemaVersion' => 1,
      'kind' => 'workbook',
      'pages' => [
        {
          'id' => 'page-main', 'name' => 'Main',
          'backgroundColor' => '#F8FAFC'
        }
      ],
      'elements' => probe_elements,
      'layout' => probe_layout
    }
  }
end

def check!(description)
  raise "FAIL — #{description}" unless yield

  puts "PASS — #{description}"
end

folder_id = home_folder_id
abort 'could not resolve a home folder id' unless folder_id

unplaced = create_spec(
  folder_id,
  probe_elements: [{ 'id' => 'orphan', 'kind' => 'text', 'body' => 'orphan' }],
  probe_layout: nil
)
code, result = json_request(:post, '/v2/workbooks/spec/verify', unplaced)
check!('verify rejects a non-empty document without layout placement') do
  !code.between?(200, 299) || result['valid'] == false
end

spec = create_spec(folder_id)
code, result = json_request(:post, '/v2/workbooks/spec/verify', spec)
check!('released layout, repeater, control refs, and new elements verify') do
  code.between?(200, 299) && result['valid'] == true
end

workbook_id = nil
begin
  code, created = json_request(:post, '/v2/workbooks/spec', spec)
  raise "POST /v2/workbooks/spec -> #{code}: #{created}" unless code.between?(200, 299)

  workbook_id = created['workbookId']
  raise "create response had no workbookId: #{created}" unless workbook_id

  code, readback = json_request(:get, "/v2/workbooks/#{workbook_id}/spec")
  raise "GET workbook spec -> #{code}: #{readback}" unless code.between?(200, 299)

  document = readback.fetch('document')
  readback_elements = document.fetch('elements')
  by_id = readback_elements.to_h { |element| [element['id'], element] }
  expected_ids = elements.map { |element| element.fetch('id') }.sort

  check!('readback keeps elements flat and pages metadata-only') do
    readback_elements.map { |element| element['id'] }.sort == expected_ids &&
      document.fetch('pages').none? { |page| page.key?('elements') }
  end
  check!('layout preserves grid, tab, and page placement tags') do
    %w[GridContainer TabbedContainer Tab LayoutElement].all? do |tag|
      document.fetch('layout').include?("<#{tag}")
    end
  end
  check!('dynamic text uses controlId and survives readback') do
    by_id.dig('dynamic-text', 'body')&.include?('[ProbeNumber]')
  end
  check!('custom SQL uses controlId and survives readback') do
    by_id.dig('sql-table', 'source', 'statement')&.include?('{{ProbeNumber}}')
  end
  check!('raw warehouse column formula is accepted and canonicalized/read back') do
    !by_id.dig('warehouse-table', 'columns', 0, 'formula').to_s.empty?
  end
  check!('repeater binding uses the derived source-name target') do
    by_id.dig('repeater-text', 'body')&.include?(
      'Sales Source repeated container/Sales Amount'
    )
  end

  %w[warehouse-table sql-table].each do |element_id|
    query = nil
    query_code = nil
    4.times do |attempt|
      query_code, query = json_request(
        :get, "/v2/workbooks/#{workbook_id}/elements/#{element_id}/query"
      )
      break if query_code.between?(200, 299) && query['sql']
      sleep(2**attempt)
    end
    check!("compiled SQL resolves for #{element_id}") do
      sql = query && query['sql'].to_s
      query_code&.between?(200, 299) && !sql.empty? &&
        sql !~ /Unknown column|Circular column reference|\{\{ProbeNumber\}\}/i
    end
  end
ensure
  if workbook_id
    code, response = json_request(:delete, "/v2/workbooks/#{workbook_id}")
    warn "WARN — cleanup DELETE returned #{code}: #{response}" unless code.between?(200, 299)
  end
end
