# Interactivity & Settings Patterns

Recipes for a plugin that does more than passively display one value —
assumes you've read `reference/sdk-api.md` for the underlying config/data/
variable/action vocabulary. Like that file, this one does not repeat
`reference/plugin-lifecycle.md`'s registration/hosting/embedding gotchas.

## Graceful loading / partial config

A plugin renders the moment it's dropped onto a canvas, before the author
has configured anything. Guide them through setup instead of showing an
error or a blank box — check state in the order the author actually fills
it in:
```js
function view(config, data) {
  if (!config.dataSource) return renderMessage('Choose a data source.');
  if (!config.metricColumn) return renderMessage('Choose a metric column.');
  const values = data[config.metricColumn];
  if (!values || values.length === 0) return renderMessage('No rows yet for this selection.');
  return renderReady(values);
}
```
No source → no column → no data → ready. Treat "ready" as the last branch
you reach, never the first thing you assume.

## JSON-settings pattern

The built-in editor-panel field types cover simple config, but not a rich,
bespoke settings UI (several color pickers, nested layout options, a form
the plugin renders itself). Route that through a single `text` field
holding a JSON blob instead of trying to model it as editor-panel fields:
```js
client.config.configureEditorPanel([
  { name: 'dataSource', type: 'element' },
  { name: 'settingsJson', type: 'text', label: 'Settings (internal — do not hand-edit)', defaultValue: '{}', multiline: true },
  { name: 'editMode', type: 'toggle', label: 'Edit Mode' }
]);

const DEFAULT_SETTINGS = {
  title: 'Untitled',
  theme: 'light',
  cardStyle: { radius: 8, shadow: true }
};

function loadSettings(raw) {
  if (!raw || !raw.trim()) return { ...DEFAULT_SETTINGS };
  try {
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_SETTINGS,
      ...parsed,
      // one level of deep merge — a flat spread alone only merges the TOP level
      cardStyle: { ...DEFAULT_SETTINGS.cardStyle, ...(parsed.cardStyle || {}) }
    };
  } catch {
    return { ...DEFAULT_SETTINGS }; // malformed JSON in the field — never throw, fall back
  }
}

function saveSettings(settings) {
  client.config.set({ settingsJson: JSON.stringify(settings) }); // persists with the workbook
}
```
Always parse in a `try/catch`, and always overlay the parsed object onto
the defaults rather than trusting it alone — that's what lets a later
plugin version add a new settings key without breaking every workbook that
saved the old shape. Settings saved this way persist with the workbook:
they survive refresh and are shared with anyone viewing it.

## Edit-mode gating

Pair an `editMode` toggle (declared above) with — or in place of — reading
`client.sigmaEnv`, to decide whether to show builder-only chrome:
```js
const showBuilderUI = config.editMode || client.sigmaEnv === 'author';
```
`editMode` is an explicit author opt-in (works even for an author who wants
viewers to see it too); `sigmaEnv` reflects the actual session
(`'author' | 'viewer' | 'explorer'`) regardless of any toggle. Gate a
settings-gear icon, inline rename handles, or debug output (row counts, raw
column IDs) behind whichever — or both — fits the plugin.

## Variable + action-trigger writeback (the headline pattern)

This is how a plugin stops passively displaying data and starts driving the
workbook. Two editor-panel fields, always declared as a pair:
```js
client.config.configureEditorPanel([
  { name: 'dataSource', type: 'element' },
  { name: 'categoryColumn', type: 'column', source: 'dataSource', label: 'Category' },
  { name: 'selected', type: 'variable', label: 'Selected Category', allowedTypes: ['text'] },
  { name: 'onSelect', type: 'action-trigger', label: 'On Select' }
]);
```
```js
const [, setSelected] = useVariable(config.selected || '');   // write-only: discard the getter
const fireOnSelect = useActionTrigger(config.onSelect || '');

function choose(rowValue) {
  setSelected(String(rowValue));  // 1. the WHAT — text variables want explicit String() coercion
  fireOnSelect?.();               // 2. the REACT-NOW — tell the workbook something changed
}

function clear() {
  setSelected('');   // clear with '' — not null
  fireOnSelect?.();
}
```
The variable carries the value; the trigger tells the workbook to notice
it. The workbook builder is the one who wires the variable into a
filter/control and the trigger into a refresh/navigate elsewhere in
Sigma — declaring both fields here is what makes that wiring possible.

**Multiple variables in one writeback** — set every value, then fire the
trigger once:
```js
const [, setId] = useVariable(config.selectedId || '');
const [, setLabel] = useVariable(config.selectedLabel || '');  // the "dual" value+label variant
const fireOnSelect = useActionTrigger(config.onSelect || '');

function choose(row) {
  setId(String(row.id));
  setLabel(String(row.name));
  fireOnSelect?.();
}
```
The dual (value + label) shape is handy whenever the consuming control
needs a human-readable label alongside the raw value it filters on.

## Dynamic editor-panel reconfiguration

Keep the panel from cluttering itself with fields the author hasn't opted
into. Recompute the config array from current config and re-call
`configureEditorPanel`:
```js
function buildPanel(writebackEnabled) {
  const base = [
    { name: 'dataSource', type: 'element' },
    { name: 'categoryColumn', type: 'column', source: 'dataSource', label: 'Category' },
    { name: 'enableWriteback', type: 'toggle', label: 'Enable Writeback' }
  ];
  if (writebackEnabled) {
    base.push(
      { name: 'selected', type: 'variable', label: 'Selected Category' },
      { name: 'onSelect', type: 'action-trigger', label: 'On Select' }
    );
  }
  return base;
}

client.config.configureEditorPanel(buildPanel(false)); // initial

client.config.subscribe((cfg) => {
  client.config.configureEditorPanel(buildPanel(!!cfg.enableWriteback)); // reconfigure on change
});
```
(React: the equivalent inside a `useEffect` keyed on `config.enableWriteback`.)
The `variable`/`action-trigger` fields don't exist in the panel at all
until the author flips `enableWriteback` on.

## Variable-value unwrapping (footgun)

The current SDK types `getVariable`/`useVariable`'s value as a fixed shape —
`{ name: string, defaultValue: { type: string, value: any } }` — so the
value itself lives at `variable.defaultValue.value`, never at the top
level. Unwrap defensively anyway: some bindings and older SDK versions have
been observed handing back a flatter `{ value }` shape, and `undefined`
shows up whenever nothing is bound yet:
```js
function unwrapVariable(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== 'object') return raw;                      // already a plain value
  if (raw.defaultValue?.value !== undefined) return raw.defaultValue.value; // current shape
  if (raw.value !== undefined) return raw.value;                 // flatter shape, seen elsewhere
  return null;
}
```
Date-typed variables have additionally been observed to carry one more
nesting level around a millisecond timestamp:
```js
function unwrapDateVariable(raw) {
  const inner = unwrapVariable(raw);
  if (inner && typeof inner === 'object' && 'date' in inner) return new Date(inner.date);
  return inner ? new Date(inner) : null;
}
```
Run every variable read through one of these before using it. This is a
footgun specifically because the documented shape works fine in quick
testing, and only some bindings surface the flatter or extra-nested cases.

## Action-effect (workbook → plugin)

The inverse of a trigger: the workbook calls into the plugin.
```js
client.config.configureEditorPanel([
  { name: 'onReset', type: 'action-effect', label: 'Reset Plugin' }
]);
```
```js
useActionEffect(config.onReset || '', () => {
  clearSelection();
  resetToDefaults();
});
```
Typical uses: a workbook-level "reset all filters" control also resets this
plugin's internal state, or a scheduled/triggered workbook action tells the
plugin to refresh.

## Multi-column roles

A plugin needing several distinct roles from the same element (an x-axis,
a y-axis, a label, a set of tooltip fields) declares one `column` entry per
role, all pointing at the same `source`:
```js
client.config.configureEditorPanel([
  { name: 'dataSource', type: 'element' },
  { name: 'xAxis', type: 'column', source: 'dataSource', label: 'X Axis' },
  { name: 'yAxis', type: 'column', source: 'dataSource', label: 'Y Axis' },
  { name: 'seriesLabel', type: 'column', source: 'dataSource', label: 'Series Label' },
  { name: 'tooltipFields', type: 'column', source: 'dataSource', allowMultiple: true, label: 'Tooltip Fields' }
]);
```
`allowMultiple: true` can hand back a single string OR an array depending
on how many columns are currently picked — always normalize before use:
```js
const tooltipIds = Array.isArray(config.tooltipFields)
  ? config.tooltipFields
  : [config.tooltipFields].filter(Boolean);
```

## Worked writeback example — click-to-filter list (documented recipe, not yet live-verified)

The rest of this file has been individual recipes; this ties graceful
loading, a single-column read, and variable + action-trigger writeback
together into one small vanilla-JS plugin. It renders a category column as
a clickable list; clicking a row writes a `selected` variable and fires an
`onSelect` action-trigger so the workbook can filter something else off the
choice.

**Honesty note:** unlike the gauge plugin shipped with this skill — which
has been registered, embedded, and value-verified against a live
workbook — this recipe has **not** been rendered end-to-end against a live
Sigma org. Doing that needs a workbook with a control and an action already
wired to `selected`/`onSelect`, which is a live-workbook setup step outside
a reference document. Treat this as a documented, SDK-correct starting
point to adapt and verify yourself — not as a pre-verified artifact.

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Click-to-filter list (recipe)</title>
<style>
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  #list-root { padding: 8px; }
  .list-row { padding: 6px 10px; cursor: pointer; border-radius: 4px; }
  .list-row:hover { background: #f3f4f6; }
  .list-row.is-active { background: #e0e7ff; font-weight: 600; }
  .list-empty { color: #6b7280; padding: 8px; }
</style>
</head>
<body>
<div id="list-root"><div class="list-empty">Loading…</div></div>

<script crossorigin src="https://unpkg.com/react@18.3.1/umd/react.production.min.js"></script>
<script src="https://unpkg.com/@sigmacomputing/plugin"></script>
<script>
(function () {
  'use strict';

  // Loaded via the CDN <script> tag, the SDK's UMD build exposes its named
  // exports (client, useConfig, ...) on a `window.SigmaPlugin` global rather
  // than through an import statement. React must load first — it's a hard
  // peer dependency of the UMD build, which dereferences it at load and,
  // if absent, throws before assigning `client`, leaving no client at all
  // (not just a null one). No client (e.g. this file opened directly in a
  // browser, or React missing) -> render a static demo list, no writeback
  // wired.
  var client = (typeof window.SigmaPlugin !== 'undefined') ? window.SigmaPlugin.client : null;
  var root = document.getElementById('list-root');

  function showMessage(text) {
    root.innerHTML = '';
    var msg = document.createElement('div');
    msg.className = 'list-empty';
    msg.textContent = text;
    root.appendChild(msg);
  }

  function paintList(labels, activeLabel, onPick) {
    if (!labels.length) return showMessage('No rows for this selection.');
    root.innerHTML = '';
    labels.forEach(function (label) {
      var row = document.createElement('div');
      row.className = 'list-row' + (label === activeLabel ? ' is-active' : '');
      row.textContent = label;
      row.addEventListener('click', function () { onPick(label); });
      root.appendChild(row);
    });
  }

  if (!client) {
    paintList(['North', 'South', 'East', 'West'], null, function () {});
    return;
  }

  client.config.configureEditorPanel([
    { name: 'source', type: 'element' },
    { name: 'categoryColumn', type: 'column', source: 'source', allowMultiple: false, label: 'Category Column' },
    { name: 'selected', type: 'variable', label: 'Selected Category', allowedTypes: ['text'] },
    { name: 'onSelect', type: 'action-trigger', label: 'On Select' }
  ]);

  var unsubData = null;
  var activeLabel = null;

  function handlePick(config, labels, label) {
    activeLabel = label;
    // 1. the WHAT — set the variable (text variables want String() coercion).
    client.config.setVariable(config.selected, String(label));
    // 2. the REACT-NOW — tell the workbook to notice it.
    client.config.triggerAction(config.onSelect);
    paintList(labels, activeLabel, function (nextLabel) { handlePick(config, labels, nextLabel); });
  }

  client.config.subscribe(function (config) {
    if (unsubData) { unsubData(); unsubData = null; }

    if (!config.source) return showMessage('Choose a data source.');
    if (!config.categoryColumn) return showMessage('Choose a category column.');

    unsubData = client.elements.subscribeToElementData(config.source, function (data) {
      var values = data[config.categoryColumn];
      if (!values || !values.length) return showMessage('No rows for this selection.');

      var labels = Array.from(new Set(values.filter(function (v) { return v !== null; })));
      paintList(labels, activeLabel, function (label) { handlePick(config, labels, label); });
    });
  });
})();
</script>
</body>
</html>
```
