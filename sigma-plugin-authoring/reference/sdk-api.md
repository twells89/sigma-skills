# SDK API Reference — Editor Panel, Client, and Hooks

Lookup-oriented reference for the `@sigmacomputing/plugin` surface a plugin
uses to declare its data contract (the editor panel) and read/write
config, element data, variables, and actions once embedded. It does **not**
cover getting a plugin registered, hosted, or embedded — that's
`reference/plugin-lifecycle.md` (masked 404/403 on registration, `url`
set-once, the localhost/hosting boundary, the bare-string `config` shape,
the hidden backing page, `ResizeObserver`, the synthetic-fallback
convention). Read that first if you haven't shipped a plugin before; this
file assumes it and only adds the authoring surface.

Every fact below is checked against the SDK's own published type
declarations (`@sigmacomputing/plugin`, npm/GitHub — `sigmacomputing/plugin`,
MIT — a different, unrestricted source from the clean-room secondary
material this reference otherwise drew guidance from). Where the two
disagreed, this file follows the published types and says so.

## 1. Editor-panel config types

`client.config.configureEditorPanel([...])` (or the `useEditorPanelConfig`
hook, called once per render inside a component) declares the fields a
workbook author fills in from Sigma's side panel for this plugin element.
Every entry needs a unique `name` — the key you read its value back under —
and a `type`. One of each type, with the properties specific to it:

**`element`** — the one data-source picker every data-driven plugin needs.
```js
{ name: 'dataSource', type: 'element' }
```
Every `column`/`variable`-adjacent entry that needs to scope to it names it
via `source: 'dataSource'`.

**`column`** — pick a column out of an `element` entry.
```js
{
  name: 'metricColumn',
  type: 'column',
  source: 'dataSource',                  // required — the element entry to pick from
  allowMultiple: false,                  // true -> string[]; false -> string
  allowedTypes: ['number', 'integer'],   // restrict to specific ValueType(s)
  label: 'Metric'
}
```

**`text`** — free-form string input; the backbone of the JSON-settings
pattern (`patterns.md`) when paired with `multiline: true`.
```js
{
  name: 'title', type: 'text', label: 'Panel Title',
  defaultValue: '', placeholder: 'Untitled panel',
  multiline: false,   // true renders a textarea
  secure: false         // true masks input and omits it from pre-hydrated/URL config
}
```

**`toggle`** / **`checkbox`** — both resolve to a `boolean`; pick whichever
label style reads better in the panel. Both accept an optional
`defaultValue: boolean`.
```js
{ name: 'showLegend', type: 'toggle', label: 'Show Legend', defaultValue: true }
```

**`radio`** — small fixed choice set.
```js
{
  name: 'orientation', type: 'radio',
  values: ['vertical', 'horizontal'],
  singleLine: true,       // render inline instead of stacked — good for 2-3 options
  defaultValue: 'vertical',
  label: 'Orientation'
}
```

**`dropdown`** — larger fixed choice set.
```js
{
  name: 'aggregation', type: 'dropdown',
  values: ['sum', 'avg', 'min', 'max'],
  width: '160',            // pixel width — the SDK types this as a string, not a number
  defaultValue: 'sum',
  label: 'Aggregation'
}
```

**`color`** — a color-picker input; value is a color string.
```js
{ name: 'accentColor', type: 'color', label: 'Accent Color' }
```

**`variable`** — bind to a workbook control variable; the read/write half
of interactivity (see the writeback pattern in `patterns.md`).
```js
{
  name: 'activeCategory', type: 'variable', label: 'Active Category',
  allowedTypes: ['text']   // restrict to a ControlType — see enum below
}
```

**`interaction`** — bind to cross-element selection state.
**Deprecated as of the current published SDK — "Use Action API instead."**
The type still exists and the `client.config.getInteraction`/`setInteraction`
methods still work, but new plugins should reach for `action-trigger` +
`action-effect` (below) instead of `interaction` for cross-element behavior.
```js
{ name: 'crossSelect', type: 'interaction', label: 'Selection Binding' } // legacy
```

**`action-trigger`** — the plugin fires a workbook action.
```js
{ name: 'onSelect', type: 'action-trigger', label: 'On Select' }
```
Paired with a `variable` for the headline writeback pattern: set the
variable (the *what*), then fire the trigger (the *react now*).

**`action-effect`** — the workbook invokes a callback inside the plugin;
the inverse direction of `action-trigger`.
```js
{ name: 'onReset', type: 'action-effect', label: 'Reset Plugin' }
```

**`url-parameter`** — sync a value to the page URL for deep-linking. Note:
this type's own declared shape omits `label` — it has no display label.
```js
{ name: 'deepLinkFilter', type: 'url-parameter' }
```

**`group`** — a purely visual grouping of related entries in the panel; no
`source` property (unlike `column`/`dropdown`) and no runtime config value
of its own.
```js
{ name: 'advanced', type: 'group', label: 'Advanced' }
```

### Config-value-by-type

What `client.config.getKey(name)` / `useConfig()` hands back for each type:

| Config `type` | Runtime value |
|---|---|
| `element` | `string` (element ID) or `undefined` until chosen |
| `column`, `allowMultiple: false` | `string` (column ID) or `undefined` |
| `column`, `allowMultiple: true` | `string[]` |
| `text` | `string` |
| `toggle` / `checkbox` | `boolean` |
| `radio` / `dropdown` | one member of `values` |
| `color` | `string` |
| `variable` | `string` — a config ID; pass it to `getVariable`/`useVariable`, it is not the variable's value |
| `interaction` (deprecated) | `string` — a config ID; pass to `getInteraction`/`setInteraction` |
| `action-trigger` | `string` — a config ID; pass to `triggerAction`/`useActionTrigger` |
| `action-effect` | `string` — a config ID; pass to `registerEffect`/`useActionEffect` |
| `url-parameter` | `string` — a config ID; pass to the URL-parameter methods |
| `group` | no runtime value — structural only |

### ControlType (valid `allowedTypes` for a `variable` entry)
`'boolean' | 'date' | 'number' | 'text' | 'text-list' | 'number-list' | 'date-list' | 'number-range' | 'date-range'`

### ValueType (valid `allowedTypes` for a `column` entry)
`'boolean' | 'datetime' | 'number' | 'integer' | 'text' | 'variant' | 'link' | 'error'`

## 2. Reading config & data — two idioms

> ⚠️ **Load React before the SDK.** The UMD build
> (`<script src="https://unpkg.com/@sigmacomputing/plugin">`) has React as a
> hard peer dependency and **throws at load if React is absent**, leaving
> `window.SigmaPlugin` with no `client` — so *none* of the calls below work and
> the plugin silently synths. Put a React `<script>` (React alone; ReactDOM not
> needed for `client`) before the SDK. Full detail + the fix snippet:
> `reference/plugin-lifecycle.md` §7.

Every read/write has a vanilla `client.*` form and, in a React plugin, a
hook form; both talk to the same underlying channel. Pick one idiom per
file — don't mix them for the same value.

**Namespace note:** several of these live under `client.config.*` in the
current published SDK even though they aren't strictly about "config" —
`getVariable`/`setVariable`, `getInteraction`/`setInteraction`,
`triggerAction`, `registerEffect`, `setLoadingState`, and the
URL-parameter methods are all `client.config.X`, not top-level `client.X`.
Only `client.elements.*`, `client.style.*`, `client.sigmaEnv`, and
`client.destroy()` sit outside `config`.

### Side-by-side

| Concern | Vanilla client API | React hook |
|---|---|---|
| Define the editor panel | `client.config.configureEditorPanel(entries)` | `useEditorPanelConfig(entries)` |
| Read all config | `client.config.get()` / `client.config.subscribe(cb)` | `useConfig()` |
| Read one config value | `client.config.getKey(name)` | `useConfig(name)` or destructure from `useConfig()` |
| Write config | `client.config.set(partial)` / `client.config.setKey(name, value)` | same calls — there's no separate writer hook |
| Element data | `client.elements.subscribeToElementData(sourceId, cb)` | `useElementData(sourceId)` |
| Column metadata | `client.elements.subscribeToElementColumns(sourceId, cb)` | `useElementColumns(sourceId)` |
| Variable read/write | `client.config.getVariable(id)` / `client.config.setVariable(id, ...values)` / `client.config.subscribeToWorkbookVariable(id, cb)` | `const [variable, setVariable] = useVariable(id)` |
| Fire an action | `client.config.triggerAction(id)` | `const fire = useActionTrigger(id); fire()` |
| Receive an action | `client.config.registerEffect(id, cb)` — returns an unsubscribe fn | `useActionEffect(id, cb)` |
| Interaction (selection) — **deprecated**, prefer action-trigger/-effect | `client.config.getInteraction(id)` / `client.config.setInteraction(id, elementId, selection)` | `useInteraction(id, elementId)` — also deprecated |
| URL parameter | `client.config.getUrlParameter(name)` / `client.config.setUrlParameter(name, value)` / `client.config.subscribeToUrlParameter(name, cb)` | `useUrlParameter(name)` |
| Style | `client.style.get()` / `client.style.subscribe(cb)` | `usePluginStyle()` |
| Environment | `client.sigmaEnv` | same — a plain property, no hook needed |
| Loading indicator | `client.config.setLoadingState(bool)` | `useLoadingState(initialBool)` returns `[isLoading, setIsLoading]` |
| Teardown | `client.destroy()` | handled by component unmount in practice |

The SDK also ships `usePlugin()` (the whole `PluginInstance`) and
`usePaginatedElementData`/`elements.fetchMoreElementData` (data beyond the
default page size) — real, but out of scope for this reference; see the
package's own README for those.

### Vanilla client API surface
```js
import { client } from '@sigmacomputing/plugin';

client.config.configureEditorPanel(entries);
client.config.get();                        // full config object, once
client.config.getKey('metricColumn');        // one value, once
client.config.set({ title: 'New Title' });   // shallow merge into current config
client.config.setKey('title', 'New Title');  // write a single key
const stopConfig = client.config.subscribe((cfg) => { /* runs on every change */ });

client.elements.subscribeToElementData(sourceId, (data) => { /* column-oriented rows */ });
client.elements.subscribeToElementColumns(sourceId, (cols) => { /* metadata */ });

client.config.getVariable(varId);                        // { name, defaultValue: { type, value } }
client.config.setVariable(varId, newValue);               // range variables take 2 args
const stopVar = client.config.subscribeToWorkbookVariable(varId, (v) => {});

client.config.triggerAction(actionId);
const stopEffect = client.config.registerEffect(effectId, () => { /* workbook triggered this */ });

client.config.getUrlParameter('deepLinkFilter');           // { value: string }
client.config.setUrlParameter('deepLinkFilter', 'east-region');
const stopUrl = client.config.subscribeToUrlParameter('deepLinkFilter', (v) => {});

client.style.get();               // Promise<{ backgroundColor: string }> — workbook theme
client.style.subscribe((style) => {});

client.sigmaEnv;                  // 'author' | 'viewer' | 'explorer'
client.config.setLoadingState(true);  // show/hide Sigma's own loading indicator for this element
client.destroy();                 // tear down every subscription this client created
```
`setVariable`/`setKey`/`set`/`triggerAction` are declared to return `void`
(they post a message to the host and don't hand back a result to await).
Some example code still wraps them in `await` anyway — harmless on a
non-`Promise` return, and it defers the next statement to a microtask,
which is a cheap way to make sure a variable write has a moment to
propagate before a dependent trigger fires.

### React hooks
```js
import {
  useConfig, useEditorPanelConfig,
  useElementData, useElementColumns,
  useVariable, useActionTrigger, useActionEffect
} from '@sigmacomputing/plugin';

useEditorPanelConfig(entries);                    // define the panel from inside a component
const config = useConfig();                       // all config values, re-renders on change
const rows = useElementData(config.dataSource || '');
const cols = useElementColumns(config.dataSource || '');
const [variable, setVariable] = useVariable(config.activeCategory || '');
const fireOnSelect = useActionTrigger(config.onSelect || '');
useActionEffect(config.onReset || '', () => { /* workbook told the plugin to reset */ });
```
Guard every hook call with `|| ''` when the underlying config key might
still be `undefined` — the plugin renders before the author finishes
configuring it (see the graceful-loading pattern in `patterns.md`).

## 3. Element data shape

Data from `useElementData`/`subscribeToElementData` is **column-oriented**:
```ts
{ [columnId: string]: any[] }   // the SDK types values loosely; in practice
                                 // each entry is a string, number, boolean, or null
```
Every column array is the same length (one entry per row).

**Column IDs are not display names.** A key like `col-3f8a1c` says nothing
about what the column *is* — resolve the human-readable name from the
parallel column-metadata object (`useElementColumns`/`subscribeToElementColumns`):
```ts
{
  [columnId: string]: {
    id: string;
    name: string;         // display name, e.g. "Order Total"
    columnType: string;   // ValueType — 'text' | 'number' | 'integer' | 'datetime' | 'boolean' | ...
    // Commonly also carries a `format` object at runtime — { type: string, format: string } —
    // with a d3-format string for numeric types (e.g. "$,.2f") or a d3-time-format string for
    // date/datetime types (e.g. "%Y-%m-%d"). This isn't part of the published column-metadata
    // type as of SDK v1.2.0, so read it defensively: `columnMeta?.format?.format`.
  }
}
```

### Column → row transform
Most rendering libraries want rows, not columns:
```js
function toRows(columnData, columnIds, columnMeta) {
  const length = columnData[columnIds[0]]?.length ?? 0;
  const rows = [];
  for (let i = 0; i < length; i++) {
    const row = {};
    for (const id of columnIds) {
      const key = columnMeta?.[id]?.name ?? id;
      row[key] = columnData[id][i];
    }
    rows.push(row);
  }
  return rows;
}
```

## 4. Defensive date handling

Dates can arrive as an ISO string, a numeric timestamp (epoch seconds *or*
milliseconds — inconsistent across sources), or an already-constructed
`Date`. Never assume one shape:
```js
function parseDate(raw) {
  if (raw === null || raw === undefined) return null;
  if (raw instanceof Date) return isNaN(raw.getTime()) ? null : raw;
  if (typeof raw === 'number') {
    // Below ~10 billion, treat as epoch seconds; otherwise it's already milliseconds.
    const ms = raw < 1e10 ? raw * 1000 : raw;
    const d = new Date(ms);
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof raw === 'string') {
    const d = new Date(raw);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}
```
Use the column-metadata `format.format` (a d3-time-format string, when
present — see the hedge above) if you need to render a date the way Sigma
would, rather than hard-coding a display format.

This is a **column-value** parsing concern. A *variable's* date value has
its own, different wrapping problem (an extra object layer, not a type
ambiguity) — see the unwrap recipe in `patterns.md`.
