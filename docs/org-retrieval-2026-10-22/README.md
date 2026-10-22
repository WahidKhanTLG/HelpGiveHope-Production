# Help Give Hope production metadata retrieval - 22 October 2026

Retrieved the connected production org through Metadata API 68.0 without change tracking or modified-date filters. Both changed and unchanged metadata were requested. This is a metadata/source export; org records were not exported and nothing was deployed or published.

## Verified org

- Alias: `HelpGiveHope-Production`
- Username: `hghtlg@thelodestonegroup.com`
- Org: `Help Give Hope`, `00DHp000009vCJ4MAM`, Enterprise Edition, `IsSandbox=false`, instance `USA376`.
- Metadata describe returned 260 top-level types. Inventory covered top-level types, children, installed packages, and all exposed report, dashboard, document, and email folders.

## Retrieved files

- 41,465 converted source files under `force-app`.
- 6,782 original metadata/reference files, including five components in three types unsupported by the CLI registry.
- 48,247 retrieved files copied and verified by SHA-256; see `files.sha256`.
- 9,693 existing files were retrieved unchanged; 837 existing source files changed and 30,935 source paths are new.
- All metadata XML and metadata JSON parsed successfully. Recognized Salesforce `(hidden)` package placeholders were retained verbatim as reference files. Credential scans found no matches.

Object translations were retrieved with object definitions so field translations were included. The resulting source contains 32,532 field translation files. LWR sites were retrieved through `DigitalExperienceBundle`; the Aura site was retrieved through `SiteDotCom`.

Managed LWC/Aura bundles were retrieved separately by namespace to avoid the duplicate folder names returned in a combined package. Managed Apex, Visualforce, and static resources are kept with those original files in `metadata-reference/installed-packages`, outside the project's default package directory. Protected implementations remain unavailable; Salesforce returned 4,277 `(hidden)` reference files.

## Exceptions and retained prior files

Salesforce's APIs do not provide an unrestricted whole-org backup. Private-folder documents, non-customizable/protected fields and objects, disabled system list views, and the old `ConversationServiceIntegration`/`WebApplication` settings were not retrievable. Of 142 known standard value sets explicitly requested, 56 were returned; the other feature-specific names were inaccessible or unsupported in this org.

`ExperienceBundle` warnings are covered by the LWR `DigitalExperienceBundle` and Aura `SiteDotCom` exports. The 48 `WorkflowFlowAutomation` aliases reported by inventory were rejected under that type; their corresponding 48 `Flow` definitions were retrieved. Managed layout and global action names were corrected for namespaces and all retry requests succeeded without warnings. All server responses, including resolved initial warnings, are in `warnings.json` and `summary.json`.

158 pre-existing paths were retained because Salesforce did not return them at the same source path, including two generated local LWC configuration files and older report/dashboard aliases. These files are listed in `unrefreshed-local-files.txt` and are excluded from the verified fresh-file count. Explicit requests were made for the metadata paths omitted from the current inventory. 192 obsolete files inside fully refreshed static-resource bundles were removed; their paths are in `removed-static-assets.txt`.

## Repository handoff and validation

The two September retrieval commits were fast-forwarded into local `main` before this snapshot. Pre-existing `.forceignore` edits and the untracked `lwc/tsconfig.json` were preserved byte-for-byte and are excluded from the snapshot commit. A pre-retrieval archive remains locally outside Git.

The full source manifest was regenerated from the actual converted source and the project API version is now 68.0. Each installed-package reference folder has its own manifest. The three additional raw metadata types are in `metadata-reference/metadata-api/extra-types` with their manifest. Metadata API inventories and retrieval jobs are recorded in `inventory.json` and `summary.json`.

Validation covered org identity, successful retrieval jobs, archive paths and duplicate checks for the namespace exports, metadata parsing, credential scans, and SHA-256 comparison after copying. Apex tests and deployment validation were not run because this task only retrieved and committed existing org metadata.

`git diff --cached --check` reports whitespace in retrieved org source, including mixed indentation and trailing spaces. The exported file bytes were preserved. All 48,247 fresh source/reference paths were confirmed present in the Git index.
