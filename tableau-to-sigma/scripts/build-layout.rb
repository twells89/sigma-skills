#!/usr/bin/env ruby
# Build layout XML for a Sigma workbook spec and write it back out as JSON.
#
# Usage:
#   ruby scripts/build-layout.rb --spec /tmp/current-spec.yaml --output /tmp/workbook-with-layout.json
#
# The script reads the current spec (YAML from GET /v2/workbooks/<id>/spec), builds
# layout XML using the server-assigned element IDs, and writes JSON ready for PUT.
#
# Customize the LAYOUTS hash below for each page in your workbook.

require 'yaml'
require 'json'
require 'date'
require 'optparse'

# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

def gc(eid, c0, c1, r0, r1, inner)
  "<GridContainer elementId=\"#{eid}\" type=\"grid\" " \
  "gridColumn=\"#{c0} / #{c1}\" gridRow=\"#{r0} / #{r1}\" " \
  "gridTemplateColumns=\"repeat(24, 1fr)\" gridTemplateRows=\"auto\">\n#{inner}\n</GridContainer>"
end

def le(eid, c0, c1, r0, r1)
  "<LayoutElement elementId=\"#{eid}\" gridColumn=\"#{c0} / #{c1}\" gridRow=\"#{r0} / #{r1}\"/>"
end

def page_xml(page_id, *children)
  header = "<Page type=\"grid\" gridTemplateColumns=\"repeat(24, 1fr)\" gridTemplateRows=\"auto\" id=\"#{page_id}\">"
  [header, *children, "</Page>"].join("\n")
end

# ---------------------------------------------------------------------------
# Build element name→id map for a page
# ---------------------------------------------------------------------------

def element_map(page)
  page['elements'].each_with_object({}) { |e, h| h[e['name']] = e['id'] }
end

# ---------------------------------------------------------------------------
# Layout builders per page
# Customize this section for your specific workbook.
# Each method receives the elements hash (name → server id) and returns XML.
# ---------------------------------------------------------------------------

def layout_overview(page_id, els)
  container = els['KPI Row']
  kpi1      = els['Total Sales']
  kpi2      = els['Total Profit']
  kpi3      = els['Profit Ratio']
  kpi4      = els['Sales per Customer']
  line      = els['Monthly Sales by Segment']
  bar1      = els['Monthly Sales by Category']
  bar2      = els['Sales by Ship Mode']

  if container && kpi1
    kpi_inner = [
      le(kpi1,  1,  7, 1, 2),
      le(kpi2,  7, 13, 1, 2),
      le(kpi3, 13, 19, 1, 2),
      le(kpi4, 19, 25, 1, 2)
    ].join("\n")
    page_xml(page_id,
      gc(container, 1, 25, 1, 7, kpi_inner),
      le(line, 1, 25, 7, 20),
      le(bar1, 1, 13, 20, 32),
      le(bar2, 13, 25, 20, 32)
    )
  else
    rows = 1
    children = els.values.map do |eid|
      x = le(eid, 1, 25, rows, rows + 12)
      rows += 12
      x
    end
    page_xml(page_id, *children)
  end
end

def layout_product(page_id, els)
  bar_sub   = els['Sales by Sub-Category'] || els.values[0]
  bar_cat   = els['Profit by Category']    || els.values[1]
  tbl       = els['Product Detail Table']  || els.values[2]
  children  = [
    le(bar_sub, 1, 13, 1, 16),
    le(bar_cat, 13, 25, 1, 16),
    (le(tbl, 1, 25, 16, 36) if tbl)
  ].compact
  page_xml(page_id, *children)
end

def layout_customers(page_id, els)
  bar   = els['Top Customers by Sales'] || els.values[0]
  chart = els['Sales by Segment']       || els.values[1]
  tbl   = els['Customer Detail Table']  || els.values[2]
  children = [
    le(bar, 1, 13, 1, 16),
    le(chart, 13, 25, 1, 16),
    (le(tbl, 1, 25, 16, 36) if tbl)
  ].compact
  page_xml(page_id, *children)
end

def layout_generic(page_id, els)
  rows = 1
  children = els.values.map do |eid|
    x = le(eid, 1, 25, rows, rows + 14)
    rows += 14
    x
  end
  page_xml(page_id, *children)
end

# ---------------------------------------------------------------------------
# Page name → layout builder dispatch
# Add entries here for each named page in the workbook.
# ---------------------------------------------------------------------------

PAGE_LAYOUTS = {
  'Overview'   => method(:layout_overview),
  'Product'    => method(:layout_product),
  'Customers'  => method(:layout_customers),
}.freeze

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

options = {}
OptionParser.new do |opts|
  opts.on('--spec PATH',   'Path to current spec YAML (from GET /v2/workbooks/<id>/spec)') { |v| options[:spec] = v }
  opts.on('--output PATH', 'Output path for JSON with layout added')                       { |v| options[:output] = v }
end.parse!

abort "Usage: build-layout.rb --spec <path> --output <path>" unless options[:spec] && options[:output]
abort "Spec file not found: #{options[:spec]}"               unless File.exist?(options[:spec])

spec = YAML.safe_load(File.read(options[:spec]), permitted_classes: [Date, Time])

page_xmls = spec['pages'].map do |page|
  els     = element_map(page)
  builder = PAGE_LAYOUTS[page['name']] || method(:layout_generic)
  xml     = builder.call(page['id'], els)
  page.delete('layout')  # layout must NOT live on individual page objects
  puts "Built layout for page: #{page['name']} (#{els.size} elements)"
  xml
end

# Single top-level layout field containing all pages
spec['layout'] = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", *page_xmls].join("\n")

File.write(options[:output], JSON.pretty_generate(spec))
puts "\nWrote #{options[:output]}"
