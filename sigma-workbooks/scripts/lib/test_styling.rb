# frozen_string_literal: true
# test_styling.rb — run directly: ruby scripts/lib/test_styling.rb (from sigma-workbooks/)
require 'json'
require_relative 'styling'
require_relative 'composition'
$failures = 0
def check(desc); ok = yield; puts(ok ? "[ok] #{desc}" : "[FAIL] #{desc}"); $failures += 1 unless ok; end

# Deep-sort hashes/arrays so comparison to the golden file is key-order-independent.
def sort_deep(o)
  case o
  when Hash then o.keys.sort.each_with_object({}) { |k, h| h[k] = sort_deep(o[k]) }
  when Array then o.map { |e| sort_deep(e) }
  else o
  end
end

check('theme() (no args) returns the default palette') do
  Styling.theme == Styling::DEFAULT_THEME
end
check('theme(accent: nil) returns the default palette') do
  Styling.theme(accent: nil) == Styling::DEFAULT_THEME
end
check("theme(accent: '') returns the default palette") do
  Styling.theme(accent: '') == Styling::DEFAULT_THEME
end
check('DEFAULT_THEME categorical slot 0 + accent are the base blue') do
  Styling::DEFAULT_THEME[:categorical].first == '#2563EB' && Styling::DEFAULT_THEME[:accent] == '#2563EB'
end
check("theme(accent: '#FF6600') tints categorical slot 0") do
  Styling.theme(accent: '#FF6600')[:categorical].first == '#FF6600'
end
check("theme(accent: '#FF6600') tints :accent too") do
  Styling.theme(accent: '#FF6600')[:accent] == '#FF6600'
end
check('accent override leaves categorical slots 1..7 unchanged') do
  Styling.theme(accent: '#FF6600')[:categorical][1..-1] == Styling::DEFAULT_THEME[:categorical][1..-1]
end
check('accent override does not mutate DEFAULT_THEME (deep copy)') do
  Styling.theme(accent: '#FF6600')
  Styling::DEFAULT_THEME[:categorical].first == '#2563EB' && Styling::DEFAULT_THEME[:accent] == '#2563EB'
end
check('card shape: borderRadius/borderColor/borderWidth, no cornerRadius, no padding') do
  card = Styling::DEFAULT_THEME[:card]
  card['borderRadius'] == 'round' && card['borderColor'] == '#E2E8F0' && card['borderWidth'] == 1 &&
    !card.key?('cornerRadius') && !card.key?('padding')
end
check('header shape: backgroundColor + borderRadius only') do
  header = Styling::DEFAULT_THEME[:header]
  header == { 'backgroundColor' => '#0F172A', 'borderRadius' => 'round' }
end

# Composition.bands — role -> [r0, r1) band descriptors.
check('Composition.bands: kpi + hero (exec) matches the brief example') do
  out = Composition.bands([{ id: 'k', role: :kpi }, { id: 'h', role: :hero }], :exec)
  out == [
    { role: :kpi, ids: ['k'], r0: 1, r1: 7 },
    { role: :hero, ids: ['h'], r0: 7, r1: 19 }
  ]
end
check('Composition.bands: master_detail with control row') do
  out = Composition.bands([
    { id: 'ctl', role: :control },
    { id: 'master-chart', role: :master },
    { id: 'detail-tbl', role: :detail }
  ], :master_detail)
  out == [
    { role: :control, ids: ['ctl'], r0: 1, r1: 3 },
    { role: :master_detail, ids: %w[master-chart detail-tbl], r0: 3, r1: 17 }
  ]
end
check('Composition.bands: unknown pattern raises') do
  begin; Composition.bands([{ id: 'k', role: :kpi }], :nope); false
  rescue ArgumentError; true; end
end
check('Composition.bands: role not used by pattern raises') do
  begin; Composition.bands([{ id: 'm1', role: :master }], :exec); false
  rescue ArgumentError; true; end
end
check('Composition.bands: page_cols defaults to 24') do
  out = Composition.bands([{ id: 'h', role: :hero }], :exec)
  out == [{ role: :hero, ids: ['h'], r0: 1, r1: 13 }]
end

# --- chart_color, kpi_accent, format_for, header, section_card ---

check('SURFACES: all 6 verified surfaces are GO') do
  expected = %i[categorical_scheme chart_color_by container_style format_string kpi_name_color typography]
  Styling::SURFACES.keys.sort == expected.sort && Styling::SURFACES.values.all? { |v| v == true }
end

check('chart_color(theme): single-series color:{by:"single",value:} (categorical slot 0)') do
  Styling.chart_color(Styling::DEFAULT_THEME) == { 'color' => { 'by' => 'single', 'value' => '#2563EB' } }
end
check('chart_color(theme, categorical: true): workbook-level categoricalScheme patch') do
  Styling.chart_color(Styling::DEFAULT_THEME, categorical: true) ==
    { 'themeOverrides' => { 'categoricalScheme' => Styling::DEFAULT_THEME[:categorical] } }
end
check('chart_color: NO-GO chart_color_by -> {}') do
  Styling.chart_color(Styling::DEFAULT_THEME, surfaces: Styling::SURFACES.merge(chart_color_by: false)) == {}
end
check('chart_color: NO-GO categorical_scheme -> {}') do
  Styling.chart_color(Styling::DEFAULT_THEME, categorical: true,
                       surfaces: Styling::SURFACES.merge(categorical_scheme: false)) == {}
end

check('kpi_accent(theme) merges into a name object') do
  name = { 'text' => 'Revenue' }.merge(Styling.kpi_accent(Styling::DEFAULT_THEME))
  name == { 'text' => 'Revenue', 'color' => '#2563EB' }
end
check('kpi_accent: NO-GO kpi_name_color -> {}') do
  Styling.kpi_accent(Styling::DEFAULT_THEME, surfaces: Styling::SURFACES.merge(kpi_name_color: false)) == {}
end

check('format_for(:currency/:integer/:percent/:decimal) — d3-format, not Excel') do
  Styling.format_for(:currency) == { 'kind' => 'number', 'formatString' => '$,.0f' } &&
    Styling.format_for(:integer) == { 'kind' => 'number', 'formatString' => ',.0f' } &&
    Styling.format_for(:percent) == { 'kind' => 'number', 'formatString' => '.1%' } &&
    Styling.format_for(:decimal) == { 'kind' => 'number', 'formatString' => ',.2f' }
end
check('format_for: unknown semantic raises') do
  begin
    Styling.format_for(:bogus)
    false
  rescue ArgumentError
    true
  end
end
check('format_for: NO-GO format_string -> {}') do
  Styling.format_for(:currency, surfaces: Styling::SURFACES.merge(format_string: false)) == {}
end

check('header: container-style GO emits a container + title text element and a rows-1/3 GridContainer') do
  h = Styling.header(id: 'hdr', title: 'Dashboard', theme: Styling::DEFAULT_THEME)
  h[:element].length == 2 &&
    h[:element][0] == { 'id' => 'hdr-bg', 'kind' => 'container', 'style' => Styling::DEFAULT_THEME[:header] } &&
    h[:element][1]['kind'] == 'text' &&
    h[:layout].include?('<GridContainer') && h[:layout].include?('gridRow="1 / 3"') &&
    h[:layout].include?('elementId="hdr-title"')
end
check('header: NO-GO container_style emits a bare text element, no container') do
  h = Styling.header(id: 'hdr', title: 'Dashboard', theme: Styling::DEFAULT_THEME,
                      surfaces: Styling::SURFACES.merge(container_style: false))
  h[:element].length == 1 && h[:element][0]['kind'] == 'text' && !h[:layout].include?('GridContainer')
end

check('section_card: container-style GO wraps band ids in a themed card GridContainer') do
  band = { role: :kpi, ids: %w[k1 k2 k3], r0: 7, r1: 13 }
  sc = Styling.section_card(id: 'card-1', band: band, theme: Styling::DEFAULT_THEME)
  sc[:element] == { 'id' => 'card-1', 'kind' => 'container', 'style' => Styling::DEFAULT_THEME[:card] } &&
    sc[:wrap].include?('<GridContainer elementId="card-1"') && sc[:wrap].include?('gridRow="7 / 13"') &&
    sc[:wrap].scan('<LayoutElement').length == 3
end
check('section_card: NO-GO container_style returns bare band render, no container element') do
  band = { role: :kpi, ids: %w[k1 k2], r0: 1, r1: 7 }
  sc = Styling.section_card(id: 'card-1', band: band, theme: Styling::DEFAULT_THEME,
                             surfaces: Styling::SURFACES.merge(container_style: false))
  sc[:element].nil? && !sc[:wrap].include?('GridContainer') && sc[:wrap].scan('<LayoutElement').length == 2
end

golden = JSON.parse(File.read(File.join(__dir__, 'testdata', 'styling_golden.json')))
check('helpers match styling_golden.json (sorted-key identical)') do
  theme = Styling::DEFAULT_THEME
  band = { role: :kpi, ids: %w[k1 k2 k3], r0: 7, r1: 13 }
  actual = {
    'chart_color_single' => Styling.chart_color(theme),
    'chart_color_categorical' => Styling.chart_color(theme, categorical: true),
    'kpi_accent' => Styling.kpi_accent(theme),
    'format_for_currency' => Styling.format_for(:currency),
    'format_for_integer' => Styling.format_for(:integer),
    'format_for_percent' => Styling.format_for(:percent),
    'format_for_decimal' => Styling.format_for(:decimal),
    'header' => Styling.header(id: 'hdr', title: 'Dashboard', theme: theme),
    'section_card' => Styling.section_card(id: 'card-1', band: band, theme: theme)
  }
  JSON.generate(sort_deep(actual)) == JSON.generate(sort_deep(golden))
end

exit($failures.zero? ? 0 : 1)
