# Changelog

All notable changes to the Nanion Patchliner Analysis Toolkit are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.1] — 2026-06-15

### Added

- **`SubtractBaseline(w, t0, t1)`** — `Analysis_Common.ipf`  
  New shared helper in the `SIGNAL PREPROCESSING` section.  
  Subtracts the mean of a baseline window `[t0, t1]` from a wave in-place and returns the subtracted value. Eliminates duplicated inline drift-correction code that existed independently in `tempresponse()` and `AnalizarIVporCanal()`. Convention for Nanion Patchliner protocols: `[0.001, 0.011]` s (first 10 ms).

- **`Extract2DColumn(src, col, dest_path)`** — `Analysis_Utils.ipf`  
  New generic helper in a new `WAVE UTILITIES` section.  
  Extracts a single column from a 2D wave into a named 1D wave at a given path. Replaces the repeated `Make/O/N=(n) + dest[] = src[p][col]` pattern. Returns a wave reference.

- New `SIGNAL PREPROCESSING` section in `Analysis_Common.ipf` to group shared signal processing functions separately from passive property estimation.

- New `WAVE UTILITIES` section in `Analysis_Utils.ipf` to group generic wave operations separately from graph window helpers.

### Changed

- **`AnalizarIVporCanal()`** — `Analysis_IV.ipf`  
  - Drift correction replaced by `SubtractBaseline(drift_w, 0.001, 0.011)`.  
  - `SetDimLabel` calls for `IV_Results` moved outside the loop (were executing n times unnecessarily).

- **`IV_graph()`** — `Analysis_IV.ipf`  
  - Column extraction replaced by `Extract2DColumn(IV_trace, col, path)`.

- **`tempresponse()`** — `Analysis_Ramp.ipf`  
  - Drift correction replaced by `SubtractBaseline(drift_w, 0.001, 0.011)`.  
  - `SetDimLabel` calls for `pasives` wave moved outside the loop (logic fix — were executing n times unnecessarily).

- **`boltzmann_fit()`** — `Analysis_IVCurves.ipf`  
  - Signature changed: `boltzmann_fit(GV_norm, IV_res)` → `boltzmann_fit(GV_norm, IV_res, pkg_folder)`.  
  - Folder resolution via `GetDataFolder(1) + "Packages:"` removed. Caller now passes `pkg_folder` explicitly (R4 compliance — functions do not resolve paths internally).

### Fixed

- `SetDimLabel` calls in loop bodies (both `tempresponse` and `AnalizarIVporCanal`) were redundantly re-labelling the same wave dimensions on every iteration. Now executed once before the loop.

---

## [0.0] — baseline

Initial working state. Eight-module structure established:

| File | Responsibility |
|---|---|
| `Analysis_Menus.ipf` | Entry point, panel, menu functions |
| `Analysis_Utils.ipf` | Logger, helpers, `nvar_storer`, `place_cursors` |
| `Analysis_Common.ipf` | `sorting_hat`, `first_phase`, `second_phase`, `prefix_detector`, `pasivas`, `expFitRsCm` |
| `Analysis_Ramp.ipf` | `tempresponse` |
| `Analysis_IV.ipf` | `AnalizarIVporCanal`, `IV_graph`, `plot_stim`, `plot_trace`, `plot_raw_panel` |
| `Analysis_Amplitude.ipf` | `plot_amp`, `MakeTwoPanels_plot_amp`, `findamp`, `amp_saver`, `amp_retreiver`, `CursorMovedHook` |
| `Analysis_IVCurves.ipf` | `reversal_potential_fit`, `reversal_potential_nernst` (stub), `conductance_calc`, `GV_curve`, `boltzmann_fit`, `IV_normalize` |
| `Analysis_Kinetics.ipf` | `Q10_calculator`, `Arrhenius_calculator` |
