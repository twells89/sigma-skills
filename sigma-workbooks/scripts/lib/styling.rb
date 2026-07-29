# frozen_string_literal: true
# styling.rb — spec-authorable dashboard styling helpers that decorate
# Composition output: theme (palette), chart color, KPI accent, number
# format, header/section container. Ruby 2.6+, stdlib only.
require_relative 'composition'

module Styling
  # One professional, host-agnostic palette. No branding.
  DEFAULT_THEME = {
    categorical: %w[#2563EB #0EA5E9 #14B8A6 #F59E0B #8B5CF6 #EF4444 #10B981 #64748B],
    ink: '#0F172A', muted: '#64748B',
    # Verified live: field is borderRadius ("round"), borderColor/borderWidth;
    # do NOT put padding alongside border fields (POST 400).
    card: { 'backgroundColor' => '#FFFFFF', 'borderColor' => '#E2E8F0',
            'borderWidth' => 1, 'borderRadius' => 'round' },
    header: { 'backgroundColor' => '#0F172A', 'borderRadius' => 'round' },
    accent: '#2563EB'
  }.freeze

  # Returns a theme; an accent override tints categorical slot 0 + accent.
  def self.theme(accent: nil)
    return DEFAULT_THEME if accent.nil? || accent.to_s.empty?
    t = Marshal.load(Marshal.dump(DEFAULT_THEME))         # deep copy (stdlib)
    t[:categorical] = [accent.to_s] + t[:categorical][1..-1]
    t[:accent] = accent.to_s
    t
  end

  # GO/NO-GO map, seeded from a live spec-readback probe against a real Sigma
  # org: every surface below survived GET-spec readback AND rendered a real
  # pixel hit. All 6 are GO today, but gating every helper through this map
  # (instead of hardcoding `true` at each call site) means a future
  # regression/deprecation can flip one surface off in one place — the gated
  # helper then returns an empty patch instead of emitting an unverified (or
  # 400-rejected) shape.
  SURFACES = {
    kpi_name_color: true,     # name:{text,color} on a kpi-chart (value.color bonus also GO, not emitted here)
    chart_color_by: true,     # color:{by:"single",value:"#hex"} on a chart element
    categorical_scheme: true, # workbook-level themeOverrides:{categoricalScheme:[...]}
    format_string: true,      # format:{kind:"number",formatString:<d3>} — Excel-style formatString is 400-rejected, never emitted
    container_style: true,    # container style:{backgroundColor,borderRadius,borderColor,borderWidth} (borderRadius, NOT cornerRadius; never combine with padding)
    typography: true          # themeOverrides.titleFont + per-element name:{fontSize} — verified GO live, but no helper below emits it (out of scope here); kept for a complete surface map
  }.freeze

  # d3-format grammar (NOT Excel) — verified live, surviving strings.
  D3_FORMATS = {
    currency: '$,.0f',
    integer: ',.0f',
    percent: '.1%',
    decimal: ',.2f'
  }.freeze

  # Chart color patch: single-series `color:{by:"single",value:}` (categorical
  # slot 0) by default, or the workbook-level categorical-scheme patch when
  # categorical: true. NO-GO surface -> {} (nothing emitted).
  def self.chart_color(theme, categorical: false, surfaces: SURFACES)
    if categorical
      return {} unless surfaces[:categorical_scheme]
      { 'themeOverrides' => { 'categoricalScheme' => theme[:categorical] } }
    else
      return {} unless surfaces[:chart_color_by]
      { 'color' => { 'by' => 'single', 'value' => theme[:categorical][0] } }
    end
  end

  # Fragment to merge into a KPI element's `name` object: name:{text:,color:}.
  # NO-GO surface -> {} (nothing to merge).
  def self.kpi_accent(theme, surfaces: SURFACES)
    return {} unless surfaces[:kpi_name_color]
    { 'color' => theme[:accent] }
  end

  # Number-format fragment for a column's `format` field.
  # semantic: :currency / :integer / :percent / :decimal.
  def self.format_for(semantic, surfaces: SURFACES)
    return {} unless surfaces[:format_string]
    d3 = D3_FORMATS[semantic.to_sym]
    raise ArgumentError, "format_for: unknown semantic #{semantic.inspect}" if d3.nil?
    { 'kind' => 'number', 'formatString' => d3 }
  end

  # Thin full-width header band (rows 1..3): a styled `kind:container` +
  # a separate `kind:text` title child (containers have no title-rendering
  # field of their own — see reference/specification/layout.md Recipe 1),
  # plus the `<GridContainer>` layout fragment wrapping the title
  # `<LayoutElement>`. If container-style is NO-GO, returns the header as a
  # plain text element with no wrapping container (a bare `<LayoutElement>`).
  def self.header(id:, title:, theme:, page_cols: 24, surfaces: SURFACES)
    title_id = "#{id}-title"
    text_el = { 'id' => title_id, 'kind' => 'text',
                'body' => "# <span style=\"color: #FFFFFF\">#{title}</span>" }
    r0 = 1
    r1 = 3
    unless surfaces[:container_style]
      layout = "  <LayoutElement elementId=\"#{title_id}\" gridColumn=\"1 / #{page_cols + 1}\" gridRow=\"#{r0} / #{r1}\"/>"
      return { element: [text_el], layout: layout }
    end
    container_id = "#{id}-bg"
    container_el = { 'id' => container_id, 'kind' => 'container', 'style' => theme[:header] }
    layout = [
      "<GridContainer elementId=\"#{container_id}\" type=\"grid\" gridColumn=\"1 / #{page_cols + 1}\" gridRow=\"#{r0} / #{r1}\" " \
        "gridTemplateColumns=\"repeat(#{page_cols}, 1fr)\" gridTemplateRows=\"auto\">",
      "  <LayoutElement elementId=\"#{title_id}\" gridColumn=\"1 / #{page_cols + 1}\" gridRow=\"#{r0} / #{r1}\"/>",
      '</GridContainer>'
    ].join("\n")
    { element: [container_el, text_el], layout: layout }
  end

  # Wraps one Composition.bands()-style band ({role:,ids:,r0:,r1:}) in a
  # styled card container: a `kind:container` (theme[:card]) at the band's
  # page-level rect, with its ids tiled side-by-side inside (same even
  # column split Composition.band uses, on the container's own relative row
  # range). If container-style is NO-GO, returns the band's bare
  # (unwrapped) `<LayoutElement>` render, matching plain Composition output.
  def self.section_card(id:, band:, theme:, page_cols: 24, surfaces: SURFACES)
    ids = band[:ids]
    height = band[:r1] - band[:r0]
    unless surfaces[:container_style]
      wrap = Composition.band(ids.map { |i| { id: i } }, band[:r0], band[:r1], page_cols).join("\n")
      return { element: nil, wrap: wrap }
    end
    container_el = { 'id' => id, 'kind' => 'container', 'style' => theme[:card] }
    children = Composition.band(ids.map { |i| { id: i } }, 1, 1 + height, page_cols).join("\n")
    wrap = [
      "<GridContainer elementId=\"#{id}\" type=\"grid\" gridColumn=\"1 / #{page_cols + 1}\" gridRow=\"#{band[:r0]} / #{band[:r1]}\" " \
        "gridTemplateColumns=\"repeat(#{page_cols}, 1fr)\" gridTemplateRows=\"auto\">",
      children,
      '</GridContainer>'
    ].join("\n")
    { element: container_el, wrap: wrap }
  end
end
