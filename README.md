# PatchlinerTools

Igor Pro procedures for organizing and analyzing automated patch-clamp recordings from Nanion Patchliner / PatchMaster. This branch restores the version 2.0 source files from the repository's existing `v2.0` branch.

## Requirements

- Igor Pro 8 or later.
- PatchMaster recordings exported as Igor binary waves.

## Source files

| File | Purpose |
| --- | --- |
| `Analysis_Menus.ipf` | Nanion menu, main panel, protocol tabs, and button handlers. |
| `Analysis_Utils.ipf` | Logging, wave and graph helpers, and baseline subtraction. |
| `Analysis_Common.ipf` | Wave organization and passive-property estimation. |
| `Analysis.ipf` | Raw-trace displays, ramp analysis, and IV routines. |
| `Analysis_Amplitude.ipf` | Ramp-amplitude plots and cursor-based extraction. |
| `Analysis_NMExport.ipf` | Export of current traces to a NeuroMatic-style folder. |

## Loading the procedures

Place all six `.ipf` files in the Igor Pro **User Procedures** folder. Open the procedures in Igor Pro, then use **Analysis → Nanion → Panel**. Automatic `#include` wiring is not present in this version; loading only `Analysis_Menus.ipf` will not load the other modules.

Start with PatchMaster-exported waves already loaded in Igor Pro. The **Organize** tab sorts waves by channel and experiment. The **Ramp** tab provides trace visualization, ramp analysis, and amplitude extraction. The **Export** tab copies current traces to a NeuroMatic-style folder.

## Current scope and limitations

- IV analysis functions exist in `Analysis.ipf`, but the **IV** tab controls are disabled in this version.
- NeuroMatic export covers current traces; stimulus reconstruction/export is pending.
- The timing and temperature assumptions are tailored to the original Patchliner protocols and should be checked before use with other protocols.
- Conductance/IV-curve helpers and Q10/Arrhenius routines described in the [archived v0.1 README](docs/README-v0.1.md) are not included in these version 2.0 source files.
- These restored procedures have not been compiled or exercised in Igor Pro as part of this repository restoration.

The [historical v0.1 documentation](docs/README-v0.1.md) is preserved for reference. It describes a different eight-module layout and must not be used as installation instructions for these version 2.0 files.

## Release status

The source is restored for review. A license has not yet been selected, and the repository should not be described as a validated IgorExchange package or archived as a software release until its license and intended release scope are confirmed.
