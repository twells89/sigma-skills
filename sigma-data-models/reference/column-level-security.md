# Column-Level Security (CLS)

CLS rules restrict which users can see specific columns. They are defined in the `columnSecurities` array of a table element.

Each rule specifies a `criteria` (who is allowed to view) and a `restrictedColumns` list (which columns to protect). Users who do not meet the criteria cannot see the listed columns.

## No one can view

Hides the column from all users, including admins.

```json
"columnSecurities": [
  {
    "id": "cls-ssn",
    "criteria": { "kind": "no-one-can-view" },
    "restrictedColumns": ["<column-id>"]
  }
]
```

## Specific users and teams

Only the explicitly listed users and/or teams can view the column.

```json
{
  "id": "cls-finance",
  "criteria": {
    "kind": "specific-users-and-teams",
    "assignments": [
      { "type": "user", "userId": "<user-id>" },
      { "type": "team", "teamId": "<team-id>" }
    ]
  },
  "restrictedColumns": ["<column-id>"]
}
```

## User attribute

Only users whose attribute matches the required value can view the column. Useful for dynamic, attribute-based access control.

```json
{
  "id": "cls-region",
  "criteria": {
    "kind": "user-attribute",
    "assignments": [
      { "userAttributeId": "<attr-id>", "value": "<required-value>" }
    ]
  },
  "restrictedColumns": ["<column-id>"]
}
```

## Enum values

**`criteria.kind` values:** `"no-one-can-view"`, `"specific-users-and-teams"`, `"user-attribute"`

## REST CRUD alternative (Beta)

Beyond the spec-embedded `columnSecurities` array above, CLS rules are also exposed as their own REST resource, scoped to one data-model element:

- `GET/POST /v2/dataModels/{dataModelId}/elements/{elementId}/columnSecurityRules`
- `PUT/DELETE .../columnSecurityRules/{columnSecurityRuleId}`

Same `criteria` shapes as above — this isn't a new access model, just a different transport. Two field differences: the REST body uses `columns` (a list of column IDs, or the string `"all"` to cover every current *and future* column) where the spec-embedded shape uses `restrictedColumns` (list only, no `"all"` wildcard); and the REST response returns a server-generated `columnSecurityRuleId` per rule, vs. the user-supplied `id` in the spec-embedded shape.

```bash
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" -H "Content-Type: application/json" \
  -d '[{"columns": ["<column-id>"], "criteria": {"kind": "no-one-can-view"}}]' \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/elements/<elementId>/columnSecurityRules"
```

**When to use which:**

| Use case | Approach |
|---|---|
| Authoring or bulk-updating a whole data model from code (what every converter's `apply_sigma_rls.py` does today — Tableau, Power BI, Cognos, Qlik, ThoughtSpot, Sisense, QuickSight, Looker) | Spec-embedded `columnSecurities` — one PUT carries the full model, rules included |
| Adding, editing, or removing a single rule on an existing, already-published model without a full spec GET/PUT round-trip | REST CRUD — surgical, one rule at a time |

> **Untested live (Beta):** attempted against a real throwaway data model in this org (`aws-api.sigmacomputing.com`); `POST .../columnSecurityRules` returned `404 UnmatchedHandler` — a route-not-registered error, not an entitlement or not-found-record error (a fake-ID request against this same route 404'd identically, while a fake-ID request against a working endpoint returned `400`). A same-shaped non-Beta endpoint (`workbooks/{workbookId}/elements/{elementId}/columns`) resolved fine on the same host, so this looks like the Beta route not yet being rolled out to this API cluster rather than a usage mistake. The shape above is reconstructed from the OpenAPI schema and is structurally sound, but has not been confirmed against a live `200` — verify on an org where the feature is enabled before depending on it.
