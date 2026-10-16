#!/usr/bin/env ruby
# frozen_string_literal: true

# Worked example: a two-page, pixel-perfect store operating report that is
# bursted one copy per store. Writes a create envelope for POST
# /v2/reports/spec; it never calls the API. See README.md in this directory.
#
#   ruby build.rb --folder-id <folder> --connection-id <sample-db-connection> \
#     --output /tmp/store-report.json

require 'json'
require 'optparse'
require_relative '../../scripts/lib/report_builder'
require_relative 'sql'

options = {
  name: 'Cold Provisions — Monthly Store Operating Report',
  default_store: 'ST001',
  output: File.join(Dir.pwd, 'store-operating-report.json')
}
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby build.rb --folder-id ID --connection-id ID [options]'
  opts.on('--folder-id ID', 'Destination folder UUID') { |v| options[:folder_id] = v }
  opts.on('--connection-id ID', 'Connection that holds the Cold Provisions schema') { |v| options[:connection_id] = v }
  opts.on('--name NAME', 'Report name') { |v| options[:name] = v }
  opts.on('--default-store ID', 'Store selected when the report opens (default ST001)') { |v| options[:default_store] = v }
  opts.on('-o', '--output PATH', 'Output JSON path') { |v| options[:output] = v }
end.parse!
abort 'build.rb: --folder-id and --connection-id are required' unless options[:folder_id] && options[:connection_id]
CONN = options[:connection_id]

BRAND = {
  'primary' => '#2F7BBF', # glacier blue — accents, TY series
  'deep' => '#0F2A44',    # navy — header, headings
  'ink' => '#1B2430',
  'muted' => '#5F6B7A',
  'line' => '#E3E8EF',
  'surface' => '#F3F6FA',
  'paper' => '#FFFFFF',
  'success' => '#1E8E5A',
  'warning' => '#C77A0A',
  'danger' => '#C0392B',
  # series order: this year, last year, then supporting hues
  'categorical' => %w[#2F7BBF #B8C4D1 #0F2A44 #7FB7E6 #E3A857 #5C9E8F #9A7FC1 #C2C2C9],
}.freeze
TINT = '#E4EFF9'

b = ReportSpec::Builder.new(name: options[:name], folder_id: options[:folder_id],
                            paper: 'letter-portrait', margin: 32, brand: BRAND)
br = b.brand
CW = b.content_width # 752
HDR = 64
FTR = 36

# ---------- formats ----------
USD0 = { 'kind' => 'number', 'formatString' => '$,.0f' }.freeze
USD2 = { 'kind' => 'number', 'formatString' => '$,.2f' }.freeze
INT = { 'kind' => 'number', 'formatString' => ',.0f' }.freeze
PCT = { 'kind' => 'number', 'formatString' => ',.1%' }.freeze
SPCT = { 'kind' => 'number', 'formatString' => '+,.1%' }.freeze
CARD = { 'backgroundColor' => '#FFFFFF', 'borderColor' => BRAND['line'], 'borderWidth' => 1, 'borderRadius' => 'round' }.freeze

S = '[Store Summary/'
dyn = ->(col) { "{{Max(#{S}#{col}])}}" }
span = ->(s, size, color = BRAND['ink'], bold: false) { %(<span style="font-size: #{size}px; color: #{color}">#{bold ? "**#{s}**" : s}</span>) }
section = ->(id, title) { b.text(id: id, body: "**#{title.upcase}**", color: br['primary'], font_size: 10) }

# ---------- pages & furniture ----------
b.add_page(id: 'page-1', name: 'Summary')
b.add_page(id: 'page-2', name: 'Sales detail')
b.add_page(id: 'data', name: 'Data', hidden: true)
b.add_panel(id: 'hdr', type: 'header', height: HDR, pages: %w[page-1 page-2], title: 'Report header', background: br['deep'])
b.add_panel(id: 'ftr-1', type: 'footer', height: FTR, pages: %w[page-1], title: 'Footer page 1', background: br['surface'])
b.add_panel(id: 'ftr-2', type: 'footer', height: FTR, pages: %w[page-2], title: 'Footer page 2', background: br['surface'])

logo_svg = <<~SVG
  <svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
    <rect width="96" height="96" rx="22" fill="#2F7BBF"/>
    <g stroke="#FFFFFF" stroke-width="6" stroke-linecap="round" fill="none" transform="translate(48 48)">
      #{(0...6).map { |i| a = i * 60; %(<g transform="rotate(#{a})"><line x1="0" y1="0" x2="0" y2="-30"/><line x1="0" y1="-18" x2="-8" y2="-26"/><line x1="0" y1="-18" x2="8" y2="-26"/></g>) }.join}
    </g>
  </svg>
SVG
b.place(b.svg_image(id: 'hdr-logo', svg: logo_svg, fit: 'contain'), region: 'hdr', x: 20, y: 14, width: 36, height: 36)
b.place(b.text(id: 'hdr-brand', body: "**COLD PROVISIONS**", color: '#FFFFFF', font_size: 17, vertical_align: 'center'),
        region: 'hdr', x: 66, y: 14, width: 300, height: 36)
b.place(b.text(id: 'hdr-title', body: 'Monthly Store Operating Report', color: '#D6E8F5', font_size: 12, align: 'right'),
        region: 'hdr', x: CW - 20 - 320, y: 12, width: 320, height: 20)
b.place(b.text(id: 'hdr-month', body: dyn.('report_month'), color: '#9FC3E6', font_size: 10, align: 'right'),
        region: 'hdr', x: CW - 20 - 320, y: 34, width: 320, height: 18)

[['ftr-1', 1], ['ftr-2', 2]].each do |panel, n|
  b.place(b.text(id: "#{panel}-note", body: "Confidential — prepared for #{dyn.('store_name')} (#{dyn.('store_id')}) · #{dyn.('report_month')}",
                 color: br['muted'], font_size: 9, vertical_align: 'center'),
          region: panel, x: 20, y: 8, width: 560, height: 20)
  b.place(b.text(id: "#{panel}-page", body: "Page #{n} of 2", color: br['muted'], font_size: 9, align: 'right', vertical_align: 'center'),
          region: panel, x: CW - 20 - 140, y: 8, width: 140, height: 20)
end

# ---------- data page ----------
def sql_cols(prefix, cols) = cols.map { |c, f| { 'id' => "#{prefix}-#{c}", 'name' => c, 'format' => f }.compact }

summary_cols = %w[store_id store_name region tier address_line store_phone manager_name recipient_email
                  recipient_type report_month pm_label ly_label headline].map { |c| [c] }
METRICS.each do |k, _, f, _|
  fmt = { 'usd0' => USD0, 'usd2' => USD2, 'int' => INT, 'pct' => PCT }[f]
  %w[cur pm ly].each { |q| summary_cols << ["#{q}_#{k}", fmt] }
end
summary_cols += [['cur_refund_cnt', INT], ['pm_refund_cnt', INT], ['peer_net', USD0], ['peer_ticket', USD2],
                 ['peer_n', INT], ['region_rank', INT], ['region_n', INT]]

data = [
  ['src-stores', 'Store List', STORE_LIST_SQL, [['store_id'], ['store_label']]],
  ['src-summary', 'Store Summary', SUMMARY_SQL, summary_cols],
  ['src-score', 'Scorecard', SCORECARD_SQL,
   [['store_id'], ['sort_order', INT], ['metric'], ['this_month'], ['prior_month'], ['vs_prior_month', PCT],
    ['pm_signal', INT], ['last_year'], ['vs_last_year', PCT], ['ly_signal', INT], ['peer_signal', INT], ['peer_avg']]],
  ['src-daily', 'Daily', DAILY_SQL,
   [['store_id'], ['order_date'], ['day_of_month', INT], ['net_sales', USD0], ['orders', INT], ['ly_net_sales', USD0]]],
  ['src-channel', 'Channel', CHANNEL_SQL,
   [['store_id'], ['channel'], ['orders', INT], ['net_sales', USD0], ['avg_ticket', USD2], ['share', PCT]]],
  ['src-payment', 'Payment', PAYMENT_SQL, [['store_id'], ['payment_method'], ['orders', INT], ['net_sales', USD0]]],
  ['src-hourly', 'Hourly', HOURLY_SQL, [['store_id'], ['hour_label'], ['orders', INT], ['net_sales', USD0]]],
  ['src-dow', 'Day of Week', DOW_SQL,
   [['store_id'], ['dow_num', INT], ['day_of_week'], ['orders', INT], ['net_sales', USD0], ['avg_daily_sales', USD0], ['avg_ticket', USD2]]],
  ['src-exceptions', 'Exceptions', EXCEPTIONS_SQL, [['store_id'], ['reason'], ['refunded_orders', INT], ['refund_usd', USD0]]],
]
data_ids = []
data.each_with_index do |(id, name, sql, cols), i|
  b.place(b.sql_table(id: id, name: name, connection_id: CONN, statement: sql, columns: sql_cols(id, cols)),
          region: 'data', x: (i % 3) * 252, y: 80 + (i / 3) * 260, width: 240, height: 240)
  data_ids << id
end
control = {
  'id' => 'ctl-store-el', 'kind' => 'control', 'controlId' => 'store', 'controlType' => 'list', 'name' => 'Store',
  'source' => { 'kind' => 'source', 'source' => { 'kind' => 'table', 'elementId' => 'src-stores' },
                'columnId' => 'src-stores-store_id', 'displayColumnId' => 'src-stores-store_label' },
  'selectionMode' => 'single', 'value' => options[:default_store],
  'filters' => (data_ids - ['src-stores']).map { |id| { 'source' => { 'kind' => 'table', 'elementId' => id }, 'columnId' => "#{id}-store_id" } },
}
b.place(control, region: 'data', x: 0, y: 0, width: 360, height: 64)

# ---------- shared element helpers ----------
def table_el(id, source, cols, order:, sort: nil, cond: [], style: {})
  el = {
    'id' => id, 'kind' => 'table', 'source' => { 'kind' => 'table', 'elementId' => source },
    'columns' => cols, 'order' => order, 'name' => { 'visibility' => 'hidden' }, 'style' => CARD,
    'tableComponents' => { 'summaryBar' => 'hidden' },
    'tableStyle' => {
      'preset' => 'presentation', 'cellSpacing' => 'small', 'gridLines' => 'horizontal', 'banding' => 'hidden',
      'outerBorder' => 'hidden', 'headerDividerColor' => BRAND['deep'],
      'textStyles' => {
        'header' => { 'fontSize' => 10, 'fontWeight' => 'bold', 'color' => BRAND['muted'] },
        'cell' => { 'fontSize' => 11, 'color' => BRAND['ink'] },
      },
    }.merge(style),
  }
  el['sort'] = sort if sort
  el['conditionalFormats'] = cond unless cond.empty?
  el
end
col = ->(id, formula, name, fmt = nil, hidden: false, align: nil) do
  c = { 'id' => id, 'formula' => formula, 'name' => name }
  c['format'] = fmt if fmt
  c['hidden'] = true if hidden
  c['style'] = { 'align' => align } if align
  c
end
signal_fmt = ->(cols, signal_col, sign, color) do
  { 'type' => 'single', 'columnIds' => cols, 'condition' => 'formula', 'formula' => "[#{signal_col}] #{sign} 0",
    'style' => { 'color' => color, 'backgroundColor' => 'none', 'bold' => true } }
end
heat = ->(cols, scheme) { { 'type' => 'backgroundScale', 'columnIds' => cols, 'scheme' => scheme } }

kpi = ->(id, label, k, fmt, dir) do
  b.kpi(id: id, source_id: 'src-summary', label: label, value_formula: "Sum(#{S}cur_#{k}])",
        comparison_formula: "Sum(#{S}pm_#{k}])", format: fmt, direction: dir, font_size: 20)
    .tap do |e|
      e['columns'][1]['name'] = 'PM'
      e['name']['fontSize'] = 10
      e['trend'] = { 'visibility' => 'hidden' }
      e['layout']['comparisonValueOrient'] = 'below'
    end
end

# ---------- page 1: summary ----------
P1 = 'page-1'
y = 0
b.place(b.text(id: 'p1-store', body: "**#{dyn.('store_name')}**", color: br['deep'], font_size: 26), region: P1, x: 0, y: y, width: 470, height: 40)
b.place(b.text(id: 'p1-tag', body: "#{dyn.('region')} region · #{dyn.('tier')} tier", color: br['primary'], font_size: 12,
               align: 'right', vertical_align: 'bottom'), region: P1, x: 480, y: y, width: 272, height: 34)
y += 42
b.place(b.text(id: 'p1-meta', body: "#{dyn.('store_id')} · #{dyn.('address_line')} · #{dyn.('store_phone')}", color: br['muted'], font_size: 11),
        region: P1, x: 0, y: y, width: 500, height: 20)
b.place(b.text(id: 'p1-mgr', body: "Prepared for #{dyn.('manager_name')}", color: br['muted'], font_size: 11, align: 'right'),
        region: P1, x: 500, y: y, width: 252, height: 20)
y += 32

# At-a-glance callout: tinted surface + accent rule baked into SVGs; data-bound text sits beside, never over, them.
accent_svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="8" height="140" viewBox="0 0 8 140"><rect width="8" height="140" rx="4" fill="#{BRAND['primary']}"/></svg>)
b.place(b.svg_image(id: 'p1-accent', svg: accent_svg), region: P1, x: 0, y: y, width: 4, height: 66)
b.place(b.text(id: 'p1-glance-label', body: '**AT A GLANCE**', color: br['primary'], font_size: 10), region: P1, x: 16, y: y, width: 300, height: 16)
b.place(b.text(id: 'p1-glance', body: dyn.('headline'), color: br['ink'], font_size: 14), region: P1, x: 16, y: y + 18, width: CW - 16, height: 48)
y += 80

kw = 118
xs = b.computed_row(widths: [kw] * 6, gap: 8, left: 0, right: CW)
[['k-net', 'Net sales', 'net', USD0, 'higher'], ['k-orders', 'Orders', 'orders', INT, 'higher'],
 ['k-ticket', 'Avg ticket', 'ticket', USD2, 'higher'], ['k-disc', 'Discount rate', 'disc_rate', PCT, 'lower'],
 ['k-tips', 'Tips', 'tips', USD0, 'higher'], ['k-refunds', 'Refunds', 'refunds', USD0, 'lower']].each_with_index do |(id, l, k, f, d), i|
  b.place(kpi.(id, l, k, f, d), region: P1, x: xs[i], y: y, width: kw, height: 96)
end
y += 112

b.place(section.('p1-sec-score', 'Performance scorecard'), region: P1, x: 0, y: y, width: 400, height: 18)
y += 22
score_cols = [
  col.('sc-sort', '[Scorecard/sort_order]', 'sort', INT, hidden: true),
  col.('sc-pms', '[Scorecard/pm_signal]', 'pm_signal', INT, hidden: true),
  col.('sc-lys', '[Scorecard/ly_signal]', 'ly_signal', INT, hidden: true),
  col.('sc-prs', '[Scorecard/peer_signal]', 'peer_signal', INT, hidden: true),
  col.('sc-metric', '[Scorecard/metric]', 'Metric'),
  col.('sc-cur', '[Scorecard/this_month]', 'This month', align: 'right'),
  col.('sc-pm', '[Scorecard/prior_month]', 'Prior month', align: 'right'),
  col.('sc-vpm', '[Scorecard/vs_prior_month]', 'vs PM', SPCT, align: 'right'),
  col.('sc-ly', '[Scorecard/last_year]', 'Same month LY', align: 'right'),
  col.('sc-vly', '[Scorecard/vs_last_year]', 'vs LY', SPCT, align: 'right'),
  col.('sc-peer', '[Scorecard/peer_avg]', 'Region peer avg', align: 'right'),
]
score = table_el('p1-scorecard', 'src-score', score_cols,
                 order: %w[sc-sort sc-pms sc-lys sc-prs sc-metric sc-cur sc-pm sc-vpm sc-ly sc-vly sc-peer],
                 sort: [{ 'columnId' => 'sc-sort', 'direction' => 'ascending' }],
                 cond: [signal_fmt.(['sc-vpm'], 'pm_signal', '>', BRAND['success']),
                        signal_fmt.(['sc-vpm'], 'pm_signal', '<', BRAND['danger']),
                        signal_fmt.(['sc-vly'], 'ly_signal', '>', BRAND['success']),
                        signal_fmt.(['sc-vly'], 'ly_signal', '<', BRAND['danger'])],
                 style: { 'banding' => 'shown', 'bandingColor' => BRAND['surface'] })
b.place(score, region: P1, x: 0, y: y, width: CW, height: 228)
y += 244

b.place(section.('p1-sec-daily', 'Daily net sales vs. same month last year'), region: P1, x: 0, y: y, width: 500, height: 18)
y += 22
daily = {
  'id' => 'p1-daily', 'kind' => 'combo-chart', 'source' => { 'kind' => 'table', 'elementId' => 'src-daily' },
  'columns' => [
    { 'id' => 'dy-date', 'formula' => 'DateTrunc("day", [Daily/order_date])', 'name' => 'Day',
      'format' => { 'kind' => 'datetime', 'formatString' => '%b %d' } },
    { 'id' => 'dy-net', 'formula' => 'Sum([Daily/net_sales])', 'name' => 'This year', 'format' => USD0 },
    { 'id' => 'dy-ly', 'formula' => 'Sum([Daily/ly_net_sales])', 'name' => 'Same day last year', 'format' => USD0 },
  ],
  'xAxis' => { 'columnId' => 'dy-date' },
  'yAxis' => { 'columnIds' => ['dy-net', { 'columnId' => 'dy-ly', 'type' => 'line' }] },
  'barStyle' => { 'cornerRadius' => 'round' },
  'lineAreaStyle' => { 'interpolation' => 'monotone' },
  'name' => { 'visibility' => 'hidden' },
  'legend' => { 'position' => 'top-right', 'color' => BRAND['muted'], 'fontSize' => 10 },
  'style' => CARD,
}
b.place(daily, region: P1, x: 0, y: y, width: CW, height: 270)
y += 280
b.place(b.text(id: 'p1-notes', body: 'Net sales = subtotal less discounts on completed orders (excl. tax & tips). PM = prior month; LY = same month last year. ' \
                                     'Region peer avg = mean of the other stores in this region. Green/red marks favorable/unfavorable moves.',
               color: br['muted'], font_size: 9), region: P1, x: 0, y: y, width: CW, height: 52)

# ---------- page 2: detail ----------
P2 = 'page-2'
L = 460; R = CW - L - 16
lx, rx = b.computed_row(widths: [L, R], gap: 16, left: 0, right: CW)
y = 0
b.place(b.text(id: 'p2-title', body: '**Where and when the sales happened**', color: br['deep'], font_size: 20), region: P2, x: 0, y: y, width: CW, height: 32)
b.place(b.text(id: 'p2-sub', body: "#{dyn.('store_name')} · #{dyn.('report_month')} · completed orders", color: br['muted'], font_size: 11),
        region: P2, x: 0, y: y + 32, width: CW, height: 18)
y += 62

b.place(section.('p2-sec-channel', 'Sales by channel'), region: P2, x: lx, y: y, width: L, height: 18)
b.place(section.('p2-sec-pay', 'Payment mix · net sales'), region: P2, x: rx, y: y, width: R, height: 18)
y += 22
channel = table_el('p2-channel', 'src-channel', [
  col.('ch-name', '[Channel/channel]', 'Channel'),
  col.('ch-orders', '[Channel/orders]', 'Orders', INT, align: 'right'),
  col.('ch-net', '[Channel/net_sales]', 'Net sales', USD0, align: 'right'),
  col.('ch-share', '[Channel/share]', 'Share', PCT, align: 'right'),
  col.('ch-ticket', '[Channel/avg_ticket]', 'Avg ticket', USD2, align: 'right'),
], order: %w[ch-name ch-orders ch-net ch-share ch-ticket], sort: [{ 'columnId' => 'ch-net', 'direction' => 'descending' }],
   cond: [heat.(['ch-share'], ['#FFFFFF', TINT, '#9FC3E6'])])
b.place(channel, region: P2, x: lx, y: y, width: L, height: 150)
payment = {
  'id' => 'p2-payment', 'kind' => 'bar-chart', 'source' => { 'kind' => 'table', 'elementId' => 'src-payment' },
  'columns' => [
    { 'id' => 'pm-name', 'formula' => '[Payment/payment_method]', 'name' => 'Payment method' },
    { 'id' => 'pm-net', 'formula' => 'Sum([Payment/net_sales])', 'name' => 'Net sales', 'format' => USD0 },
  ],
  'xAxis' => { 'columnId' => 'pm-name', 'sort' => { 'by' => 'pm-net', 'direction' => 'descending' } },
  'yAxis' => { 'columnIds' => ['pm-net'] }, 'orientation' => 'horizontal', 'stacking' => 'none',
  'barStyle' => { 'cornerRadius' => 'round' },
  'color' => { 'by' => 'single', 'value' => BRAND['primary'] },
  'name' => { 'visibility' => 'hidden' }, 'legend' => { 'visibility' => 'hidden' }, 'style' => CARD,
}
b.place(payment, region: P2, x: rx, y: y, width: R, height: 150)
y += 168

b.place(section.('p2-sec-hour', 'Net sales by hour of day'), region: P2, x: lx, y: y, width: L, height: 18)
b.place(section.('p2-sec-dow', 'Day of week'), region: P2, x: rx, y: y, width: R, height: 18)
y += 22
hourly = {
  'id' => 'p2-hourly', 'kind' => 'bar-chart', 'source' => { 'kind' => 'table', 'elementId' => 'src-hourly' },
  'columns' => [
    { 'id' => 'hr-label', 'formula' => '[Hourly/hour_label]', 'name' => 'Hour' },
    { 'id' => 'hr-net', 'formula' => 'Sum([Hourly/net_sales])', 'name' => 'Net sales', 'format' => USD0 },
    { 'id' => 'hr-heat', 'formula' => 'Sum([Hourly/net_sales])', 'name' => 'Intensity', 'format' => USD0 },
  ],
  'xAxis' => { 'columnId' => 'hr-label', 'sort' => { 'by' => 'hr-label', 'direction' => 'ascending' } },
  'yAxis' => { 'columnIds' => ['hr-net'] }, 'stacking' => 'none',
  'barStyle' => { 'cornerRadius' => 'round' },
  'color' => { 'by' => 'scale', 'column' => 'hr-heat', 'scheme' => ['#B9D6EF', BRAND['deep']] },
  'name' => { 'visibility' => 'hidden' }, 'legend' => { 'visibility' => 'hidden' }, 'style' => CARD,
}
b.place(hourly, region: P2, x: lx, y: y, width: L, height: 292)
dow = table_el('p2-dow', 'src-dow', [
  col.('dw-num', '[Day of Week/dow_num]', 'n', INT, hidden: true),
  col.('dw-day', '[Day of Week/day_of_week]', 'Day'),
  col.('dw-avg', '[Day of Week/avg_daily_sales]', 'Avg daily sales', USD0, align: 'right'),
  col.('dw-ticket', '[Day of Week/avg_ticket]', 'Avg ticket', USD2, align: 'right'),
], order: %w[dw-num dw-day dw-avg dw-ticket], sort: [{ 'columnId' => 'dw-num', 'direction' => 'ascending' }],
   cond: [heat.(['dw-avg'], ['#FFFFFF', TINT, '#9FC3E6'])],
   style: { 'cellSpacing' => 'medium' })
b.place(dow, region: P2, x: rx, y: y, width: R, height: 292)
y += 310

b.place(section.('p2-sec-exc', 'Refunds by reason'), region: P2, x: lx, y: y, width: L, height: 18)
b.place(section.('p2-sec-quality', 'Order quality vs. prior month'), region: P2, x: rx, y: y, width: R, height: 18)
y += 22
refunds = {
  'id' => 'p2-exceptions', 'kind' => 'bar-chart', 'source' => { 'kind' => 'table', 'elementId' => 'src-exceptions' },
  'columns' => [
    { 'id' => 'ex-reason', 'formula' => '[Exceptions/reason]', 'name' => 'Reason' },
    { 'id' => 'ex-usd', 'formula' => 'Sum([Exceptions/refund_usd])', 'name' => 'Refund $', 'format' => USD0 },
  ],
  'xAxis' => { 'columnId' => 'ex-reason', 'sort' => { 'by' => 'ex-usd', 'direction' => 'descending' } },
  'yAxis' => { 'columnIds' => ['ex-usd'] }, 'orientation' => 'horizontal', 'stacking' => 'none',
  'barStyle' => { 'cornerRadius' => 'round' },
  'color' => { 'by' => 'single', 'value' => '#D9786C' },
  'dataLabel' => { 'display' => 'shown' },
  'name' => { 'visibility' => 'hidden' }, 'legend' => { 'visibility' => 'hidden' }, 'style' => CARD,
}
b.place(refunds, region: P2, x: lx, y: y, width: L, height: 196)
qw = (R - 12) / 2
qx = b.computed_row(widths: [qw, qw], gap: 12, left: rx, right: rx + R)
b.place(kpi.('k-coupon', 'Coupon redemption', 'coupon_rate', PCT, 'higher'), region: P2, x: qx[0], y: y, width: qw, height: 92)
b.place(kpi.('k-refund-rate', 'Refund rate', 'refund_rate', PCT, 'lower'), region: P2, x: qx[1], y: y, width: qw, height: 92)
b.place(kpi.('k-refund-cnt', 'Refunded orders', 'refund_cnt', INT, 'lower'), region: P2, x: qx[0], y: y + 104, width: qw, height: 92)
b.place(kpi.('k-disc2', 'Discount rate', 'disc_rate', PCT, 'lower'), region: P2, x: qx[1], y: y + 104, width: qw, height: 92)
y += 214
b.place(b.text(id: 'p2-recipient', body: "Delivered to #{dyn.('recipient_email')} (#{dyn.('recipient_type')}). " \
                                         'Questions about this report: ops-reporting@coldprovisions.com',
               color: br['muted'], font_size: 9), region: P2, x: 0, y: y, width: CW, height: 20)

spec = b.to_h(description: 'Per-store monthly operating report (last completed month), bursted by store to store managers.')
File.write(options[:output], JSON.pretty_generate(spec))
puts "wrote #{options[:output]} (#{spec['document']['elements'].size} elements)"
