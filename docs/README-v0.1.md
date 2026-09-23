# Nanion Patchliner Analysis Toolkit

An Igor Pro procedure package for analysis of automated patch clamp data acquired with the **Nanion Patchliner** system using **PatchMaster** software.

Targets the electrophysiology research community. Intended for submission to [IgorExchange](https://www.wavemetrics.com/forum/igorexchange) (WaveMetrics community platform).

---

## Requirements

- Igor Pro 8 or later
- Data acquired with Nanion Patchliner / PatchMaster (exported as Igor binary waves)

---

## Installation

1. Copy all `.ipf` files into your Igor Pro **User Procedures** folder  
   (`Igor Pro User Files/User Procedures/`)
2. In Igor Pro: **File → Open File → Procedure**, open `Analysis_Menus.ipf`  
   (remaining modules are included automatically via `#include` — _pending_)
3. From the menu bar: **Analysis → Nanion → Panel**

---

## Quick Start

1. Load your PatchMaster-exported waves into Igor Pro
2. Open the toolkit: **Analysis → Nanion → Panel**
3. In the **Organize** tab: click **Organize data** and enter your wave prefix  
   (e.g. `Cell` for waves named `Cell_001`, `Cell_002`, …)
4. Navigate to an experiment folder and select the appropriate protocol tab

---

## Module Structure

| File | Responsibility |
|---|---|
| `Analysis_Menus.ipf` | Entry point, main panel, tab control, menu functions |
| `Analysis_Utils.ipf` | Logger, global variable helpers, folder path helpers, wave utilities, graph window helpers |
| `Analysis_Common.ipf` | Signal preprocessing, wave organization (`sorting_hat`), passive property estimation (`pasivas`) |
| `Analysis_Ramp.ipf` | Ramp protocol analysis (`tempresponse`) |
| `Analysis_IV.ipf` | IV protocol analysis (`AnalizarIVporCanal`), IV and raw trace graphs |
| `Analysis_Amplitude.ipf` | Amplitude extraction from ramp fits, result wave management, cursor hook |
| `Analysis_IVCurves.ipf` | Reversal potential, chord conductance, G-V curve, Boltzmann fit, IV normalization |
| `Analysis_Kinetics.ipf` | Temperature-dependent kinetics: Q10 and Arrhenius analysis |

---

## Folder Hierarchy

After running **Organize data**, waves are moved into the following structure:

```
root:
└── chan_X:                    ← per channel (e.g. chan_A, chan_B)
    ├── Packages:              ← channel globals (Wave_prefix, chanexp)
    ├── Ramp_Analysis:         ← result waves for ramp protocol
    ├── IV_Analysis:           ← result waves for IV protocol
    └── exp_Y:                 ← per experiment
        ├── Trace:             ← current traces
        ├── Stim:              ← stimulus amplitude and duration waves
        ├── Packages:          ← experiment globals (ramp_temp, etc.)
        └── Analysis:          ← intermediate analysis waves
```

### Folder management rules

| Rule | Description |
|---|---|
| R1 | Administrative folders (`Packages`, `Trace`, `Stim`) — created by `sorting_hat` / `prefix_detector` only |
| R2 | Intermediate folders (`exp_Y:Analysis:`) — created by the analysis function that needs them |
| R3 | Result folders (`chan_X:Ramp_Analysis:`, `chan_X:IV_Analysis:`) — created by `CheckDataFolder` on first use |
| R4 | Path resolution — functions receive folder paths as parameters; no internal resolution |
| R5 | `exp_type` as explicit parameter — no function detects protocol type automatically |

---

## Analysis Workflows

### Ramp protocol

```
prefix_detector()          → organize waves into folder hierarchy
plot_raw_panel()           → visualize traces and stimulus
menu_tempresponse()        → baseline fit + peak extraction + passive properties
plot_amp("raw")            → amplitude panel with cursor-based selection
```

**Result waves** (in `chan_X:Ramp_Analysis:`):

| Wave | Columns | Units |
|---|---|---|
| `MutantName_Prefix_Chan_Amp` | [0] baseline, [1] peak, [2] delta | pA |
| `chan_fitpeak_T` | [0] mode 0 (linear fit), [2] mode 2 (no fit) | same as input |
| `chan_pasives_T` | [0] Cm, [1] tau, [2] Rs | pF, ms, MΩ |

### IV protocol

```
prefix_detector()          → organize waves
AnalizarIVporCanal()       → current, voltage, passive properties per sweep
IV_graph()                 → current vs voltage plot
```

**Result wave** `IV_Results` (in `exp_Y:Analysis:`):

| Column | Quantity | Unit |
|---|---|---|
| [0] | Current | A |
| [1] | Voltage | V |
| [2] | Cm | F |
| [3] | tau | s |
| [4] | Rs | Ω |

### IV curves (from IV_Results)

```
reversal_potential_fit(IV_res, Rs_corr)   → V_rev by zero-crossing interpolation
conductance_calc(IV_res, V_rev_mV)        → chord conductance G = I / (V - V_rev)
GV_curve(G_chord, IV_res)                 → normalized G-V: G_norm = G / G_max
boltzmann_fit(GV_norm, IV_res, pkg_folder)→ V_half and slope k
IV_normalize(IV_res)                       → normalized IV curve
```

---

## Key Design Conventions

### Cursor / active wave tracking

Every graph that uses cursors for analysis stores the active wave's full path in:

```
root:Packages:[graph_name]_wave_path
```

obtained via `GetWavesDataFolder(w, 2)`. This is required because `CsrWave()` does not work reliably with hosted subgraphs (`#` syntax). The path is consumed by `CursorMovedHook` and button procedures.

### Global variable sentinel

`nvar_storer(name, value, folder)` uses `NaN` as the retrieve-mode sentinel, so legitimate stored zero values are preserved correctly.

### Cursor placement

All cursor placement uses `/P` (point-based) flags to avoid XY-axis scaling mismatches.

---

## Analytical Methods

### Passive properties (Molleman 2003)

Estimated from the capacitive transient in response to a voltage step:

```
Rs   = ΔV / I₀         (I₀ = peak current at step onset)
Rtot = ΔV / Iss        (Iss = steady-state current)
Rm   = Rtot − Rs
τ    = RC fit time constant
Cm   = τ / Rpar        (Rpar = Rs ∥ Rm)
```

### Chord conductance (Bhatt et al. 2017 PLOS ONE)

```
G(V) = I(V) / (V − V_rev)      [nA/mV = µS]
```

### Reversal potential (Scenario 2 — experimental)

Linear interpolation at the zero-current crossing of the IV curve, with optional Rs correction following Beyder & Bhargava 2021 Sci Rep.

### Boltzmann fit

```
G_norm(V) = 1 / (1 + exp((V_half − V) / k))
```

### Q10 temperature coefficient

```
Q10 = (A_j / A_i) ^ (10 / (T_j − T_i))
```

### Arrhenius activation energy

```
ln(A) = ln(A₀) − Ea / (R · T)      →      Ea (kJ/mol) = −slope × R
```

R = 8.314 J/(mol·K); linear fit of ln(amplitude) vs 1/T (K⁻¹).

---

## References

- Molleman A (2003). *Patch Clamping: An Introductory Guide to Patch Clamp Electrophysiology*. Wiley.
- Bhatt DL et al. (2017). Chord conductance analysis in Nanion SyncroPatch. *PLOS ONE*.
- Beyder A & Bhargava A (2021). Series resistance errors in whole-cell recordings. *Scientific Reports*.
- Zgrablic G et al. (2020). Patch clamp with temperature control on Patchliner. *Bioengineering*.

---

## Development Status

| Feature | Status |
|---|---|
| Wave organization (`sorting_hat`) | ✅ Complete |
| Ramp analysis (`tempresponse`) | ✅ Complete |
| Amplitude extraction | ✅ Complete |
| IV analysis (`AnalizarIVporCanal`) | ✅ Complete |
| IV curves — Scenario 2 (experimental V_rev) | ✅ Complete |
| IV curves — Scenario 1 (Nernst/GHK V_rev) | 🔲 Stub |
| IV curves — Scenario 3 (blocker conditions) | 🔲 Stub |
| Q10 / Arrhenius kinetics | ⚠️ Functional, under review |
| Ramp mode 1 (fit near 0 mV) | 🔲 TODO |
| NeuroMatic data exporter | 🔲 Planned |
| `nT`, `t0`, `dt` from Packages globals | 🔲 TODO (currently hardcoded in `amp_saver`) |
| IPT lint + format pass | 🔲 Before IgorExchange submission |
| `#include` wiring between modules | 🔲 Before IgorExchange submission |

---

## Known Limitations

- Timing parameters in `AnalizarIVporCanal()` and `tempresponse()` are hardcoded for the current Nanion Patchliner square-pulse and ramp protocols. Adaptation to other protocols requires manual adjustment.
- `nT`, `t0`, `dt` (temperature grid) are hardcoded as `6`, `20`, `5` in `amp_saver()` and `amp_retreiver()`. Will be refactored to read from Packages globals before publication.
- `Arrhenius_calculator()` fit range is hardcoded to indices `[2, 4]`.

---

## License

_To be defined prior to IgorExchange submission._
