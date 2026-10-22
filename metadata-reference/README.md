# Original metadata reference exports

`installed-packages/<namespace>` contains the original Metadata API files for managed UI bundles, Apex, Visualforce, and static resources. Bundles are separated by namespace because Salesforce removes namespace prefixes from some returned folders. Salesforce-protected files containing `(hidden)` are retained as returned.

`metadata-api/extra-types` contains ContentWorkspace, ContentWorkspacePermission, and DebugLevel metadata not recognized by the installed Salesforce CLI registry. These folders are outside the default Salesforce package directory and each export includes its manifest.

See `docs/org-retrieval-2026-10-22/README.md` for scope, validation, and API exceptions.
