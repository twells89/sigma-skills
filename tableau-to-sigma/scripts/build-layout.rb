#!/usr/bin/env ruby
# Build layout XML for a Sigma workbook spec and write it back out as JSON.
#
# Usage:
#   ruby scripts/build-layout.rb --spec /tmp/current-spec.yaml --output /tmp/workbook-with-layout.json
#
# NOTE: This script contains generic stubs. For workbooks with named pages and
# specific element arrangements, write a custom layout script per the pattern in
# refs/workbook-layout.md rather than extending this file.

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
  "  <LayoutElement elementId=\"#{eid}\" gridColumn=\"#{c0} / #{c1}\" gridRow=\"#{r0} / #{r1}\"/>"
end

def page_xml(page_id, *children)
  header = "<Page type=\"grid\" gridTemplateColumns=\"repeat(24, 1fr)\" gridTemplateRows=\"auto\" id=\"#{page_id}\">"
  [header, *children.compact, "</Page>"].join("\n")
end

# ---------------------------------------------------------------------------
# Build element name→id map for a page
# ---------------------------------------------------------------------------

def element_map(page)
  page['elements'].each_with_object({}) { |e, h| h[e['name']] = e['id'] }
end

# ---------------------------------------------------------------------------
# KPI container helper
# IMPORTANT: inner KPI gridRow spans MUST match the container's outer gridRow span.
# gridTemplateRows="auto" does NOT expand rows to fill container height.
# A KPI at inner gridRow="1 / 2" inside an 8-row container renders as a tiny sliver.
#
# Rule: container outer gridRow "r0 / r1" → KPIs inside use gridRow "r0 / r1" too.
# For two rows of KPIs in one container (outer 1/13):
#   Row 1: inner 1/7, Row 2: inner 7/13
# ---------------------------------------------------------------------------

def kpi_container(container_id, outer_r0, outer_r1, kpi_ids)
  # Divide the container height evenly across rows of KPIs
  # Determine columns: up to 4 per row, 6 cols wide each for 4; otherwise divide 24 evenly
  cols_per_kpi = 24 / [kpi_ids.size, 4].min
  rows_of_kpis = (kpi_ids.size.to_f / (24 / cols_per_kpi)).ceil
  inner_height = outer_r1 - outer_r0
  row_height   = inner_height / rows_of_kpis

  inner = kpi_ids.each_with_index.map do |eid, i|
    row_idx = i / (24 / cols_per_kpi)
    col_idx = i % (24 / cols_per_kpi)
    c0 = col_idx * cols_per_kpi + 1
    c1 = c0 + cols_per_kpi
    r0 = outer_r0 + row_idx * row_height
    r1 = r0 + row_height
    le(eid, c0, c1, r0, r1)
  end.join("\n")

  gc(container_id, 1, 25, outer_r0, outer_r1, inner)
end

# ---------------------------------------------------------------------------
# Generic fallback layout: stack all elements full-width, 14 rows each
# ---------------------------------------------------------------------------

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
  els = element_map(page)
  xml = layout_generic(page['id'], els)
  page.delete('layout')
  puts "Built layout for page: #{page['name']} (#{els.size} elements)"
  xml
end

# Strip read-only fields that cause PUT to fail
%w[workbookId url ownerId createdBy updatedBy createdAt updatedAt latestDocumentVersion].each { |k| spec.delete(k) }

# Single top-level layout field — never set on individual page objects
spec['layout'] = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", *page_xmls].join("\n")

# Guard: empty elementIds cause PUT rejection
abort "ERROR: empty elementId found in layout XML — check element_map lookups" if spec['layout'].include?('elementId=""')

File.write(options[:output], JSON.pretty_generate(spec))
puts "\nWrote #{options[:output]}"
puts "WARNING: This script uses a generic stacked layout. For proper page layouts,"
puts "write a custom Ruby script following refs/workbook-layout.md patterns."
