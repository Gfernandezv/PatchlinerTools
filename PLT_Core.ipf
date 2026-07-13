#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

//====================================================
//   ANALYSIS
//====================================================
//
// Unified analysis module for Ramp and IV protocols.
// Functions are grouped by protocol and role.
//
// Sections:
//   COMMON VISUALIZATION — plot_raw_panel, plot_stim, plot_trace
//   RAMP ANALYSIS        — tempresponse
//   IV VISUALIZATION     — IV_graph
//   IV ANALYSIS          — AnalizarIVporCanal
//====================================================


//====================================================
//   COMMON VISUALIZATION
//   Shared between Ramp and IV protocols.
//   Functions: plot_raw_panel, plot_stim, plot_trace
//====================================================

// ------------------------------------------------------------
// Function: plot_raw_panel
// Purpose : Displays raw current traces (Trace/) and stimulus
//           waveforms (Stim/) stacked vertically in a hosted
//           panel, so X axes are aligned.
//           Top subgraph:    current traces (Y only).
//           Bottom subgraph: stimulus amplitude vs duration (XY).
// Inputs  : color_mode - 0 = single color, 1 = gradient
//           Operates on the current data folder:
//             <exp_folder>:Trace/  — current wave traces
//             <exp_folder>:Stim/   — _Amp and _Dur waves
// Outputs : none (side-effect: panel "RawPanel" created/updated)
// Notes   : Requires Wave_prefix two levels up in Packages.
//           CsrWave() does not work with hosted subgraphs ("#"),
//           so the active wave path is stored via
//           StoreCursorWavePath as root:Packages:RawPanel_wave_path.
// ------------------------------------------------------------
Function plot_raw_panel(color_mode)
    Variable color_mode

    String current_folder = GetDataFolder(1)
    String trace_folder   = current_folder + "Trace:"
    String stim_folder    = current_folder + "Stim:"
    String panel_name     = "RawPanel"
    String panel_title    = "Raw traces & Stimulus"

    // Resolve wave prefix
    String parent = ParentFolder(current_folder, 2)
    SVAR/Z w_prefix = $(parent+"Packages:Wave_prefix")
    if (!SVAR_Exists(w_prefix))
        LogError("plot_raw_panel: Wave_prefix not found in " + parent + "Packages")
        return 0
    endif

    // Build wave lists
    SetDataFolder trace_folder
    String trace_list = WaveList(w_prefix+"*", ";", "")

    SetDataFolder stim_folder
    String amp_list = WaveList("*_Amp", ";", "")
    String dur_list = WaveList("*_Dur", ";", "")

    SetDataFolder current_folder

    Variable nTrace = ItemsInList(trace_list)
    Variable nStim  = min(ItemsInList(amp_list), ItemsInList(dur_list))

    if (nTrace == 0)
        LogError("plot_raw_panel: no trace waves found in " + trace_folder)
        return 0
    endif
    if (nStim == 0)
        LogError("plot_raw_panel: no stimulus waves found in " + stim_folder)
        return 0
    endif

    // Recreate panel (kill if exists to reset contents)
    if (WinType(panel_name))
        KillWindow/Z $panel_name
    endif

    // Panel layout (vertical — shared X axis):
    //   W=(left, top, right, bottom) in pixels relative to panel origin.
    //   Both subgraphs share identical left/right margins so X axes align.
    //   Traces subgraph: top half    (rows  35–305)
    //   Stim subgraph  : bottom half (rows 320–530)
    NewPanel/K=1/N=$panel_name/W=(1033,68,1550,618) as panel_title

    DrawText 15, 30,  "Current traces"
    DrawText 15, 330, "Stimulus"

    // Create hosted subgraphs — stacked vertically, same left/right bounds
    Display/HOST=$panel_name/N=Traces/W=(15,35,500,305)
    Display/HOST=$panel_name/N=Stim/W=(15,335,500,530)

    // Append waves using shared helpers
    AppendWaveListToGraph((panel_name+"#Traces"), trace_list, trace_folder)
    AppendXYWaveListToGraph((panel_name+"#Stim"), amp_list, dur_list, stim_folder)

    ColorTraces(panel_name + "#Traces", color_mode)

    // Color scale — only for gradient mode
    if (color_mode == 1)
        LoadCividis()
        ColorScale/W=$(panel_name+"#Traces")/C/N=cividis_scale ctab={0,1,Rainbow,0}, vert=0, widthPct=35, frame=0, height=5
        ColorScale/W=$(panel_name+"#Traces")/C/N=cividis_scale/F=0/Z=1/A=LT lblMargin=20,nticks=0,tickThick=0.00,logLTrip=0.1
        ColorScale/W=$(panel_name+"#Traces")/C/X=5/Y=5/N=cividis_scale "first -> last"
    endif

    // Axis labels
    Label/W=$(panel_name+"#Traces") left   "Current"
    Label/W=$(panel_name+"#Traces") bottom "Time (s)"
    Label/W=$(panel_name+"#Stim")   left   "Amplitude"
    Label/W=$(panel_name+"#Stim")   bottom "Time (s)"

    // Resolve last waves for cursor placement
    Wave stim_last  = $(stim_folder  + StringFromList(nStim-1,  amp_list))
    Wave trace_last = $(trace_folder + StringFromList(nTrace-1, trace_list))
    String stim_win  = panel_name + "#Stim"
    String trace_win = panel_name + "#Traces"

    // Cursors on Stim subgraph
    place_cursors(stim_win, stim_last, 0.3, 0.7)

    // Cursors on Traces subgraph — pending place_cursors() refactor
    //place_cursor(trace_win, trace_last, "C", 0.3)
    //place_cursor(trace_win, trace_last, "D", 0.7)

    // Store cursor wave paths for both subgraphs
    StoreCursorWavePath(panel_name,           stim_last)
    StoreCursorWavePath(panel_name+"_Traces", trace_last)

    ShowInfo/W=$panel_name

    SetWindow $panel_name, hook(killSync)=RawPanelKillHook
    StartAxisSync(panel_name, "Traces", "Stim")

    LogInfo("plot_raw_panel: " + num2str(nTrace) + " traces, " + num2str(nStim) + " stim pairs appended.")
End


// ------------------------------------------------------------
// Function: plot_stim
// Purpose : Plots stimulus waves (Amp vs Dur) from Stim folder
//           as a standalone graph. Places cursors at 30%/70%.
// Notes   : Standalone alternative to plot_raw_panel for cases
//           where only the stimulus needs to be inspected.
//           Cursor placement via place_cursors() (Utils).
// ------------------------------------------------------------
Function plot_stim()

    String current_folder = GetDataFolder(1)
    String stim_folder    = current_folder + "Stim:"
    String win_name       = "stimulus_graph"

    SetDataFolder stim_folder
    String amp_list = WaveList("*_Amp", ";", "")
    String dur_list = WaveList("*_Dur", ";", "")
    SetDataFolder current_folder

    Variable n = min(ItemsInList(amp_list), ItemsInList(dur_list))
    if (n == 0)
        LogError("plot_stim: no stimulus waves found in " + stim_folder)
        return 0
    endif

    EnsureGraphWindow(win_name, "Stimulus", 200, 200, 700, 500)
    AppendXYWaveListToGraph(win_name, amp_list, dur_list, stim_folder)

    // Place cursors on last appended wave via shared helper
    Wave yw_last = $(stim_folder + StringFromList(n-1, amp_list))
    place_cursors(win_name, yw_last, 0.3, 0.7)
    ShowInfo/W=$win_name

    StoreCursorWavePath(win_name, yw_last)
    LogInfo("plot_stim: stimulus waves appended from " + stim_folder)
End


// ------------------------------------------------------------
// Function: plot_trace
// Purpose : Plots all trace waves from the Trace subfolder
//           as a standalone graph.
// Notes   : Standalone alternative to plot_raw_panel for cases
//           where only the current traces need to be inspected.
// ------------------------------------------------------------
Function plot_trace()

    String current_folder = GetDataFolder(1)
    String trace_folder   = current_folder + "Trace:"
    String win_name       = "trace_graph"

    String parent = ParentFolder(current_folder, 2)
    SVAR/Z w_prefix = $(parent+"Packages:Wave_prefix")

    SetDataFolder trace_folder
    String y_traces = WaveList((w_prefix+"*"), ";", "")
    SetDataFolder current_folder

    Variable n = ItemsInList(y_traces)
    if (n == 0)
        LogError("plot_trace: no trace waves found in " + trace_folder)
        return 0
    endif

    EnsureGraphWindow(win_name, "Raw traces", 200, 200, 700, 500)
    AppendWaveListToGraph(win_name, y_traces, trace_folder)

    LogInfo("plot_trace: trace waves appended from " + trace_folder)
End


//====================================================
//   RAMP ANALYSIS
//====================================================

// ------------------------------------------------------------
// Function: tempresponse
// Purpose : Analyzes individual traces to extract:
//           - baseline (linear fit)
//           - peak amplitude (corrected and uncorrected)
//           - passive properties (Cm, Rs)
// Inputs  : basal_i - ramp start time (s)
//           peak_f  - peak search time (s)
//           temp    - temperature (°C)
//           chanexp - channel name string
// Outputs : Waves in Analysis subfolder:
//           - chanexp_fitpeak_T  : peak amplitudes (3 modes)
//           - chanexp_pasives_T  : Cm, tau, Rs per trace
// Notes   : Depends on Wave_prefix set by prefix_detector().
//           Baseline fit window is fixed relative to basal_i.
//           Drift correction via SubtractBaseline() (Common).
//           Column labels set once before the loop.
// ------------------------------------------------------------
Function tempresponse(basal_i, peak_f, temp, chanexp)
    Variable basal_i, peak_f, temp
    String chanexp

    Variable i
    String list, unidadY

    Variable t_ini = basal_i
    LogInfo("Baseline fit start: " + num2str(t_ini) + " s")
    LogInfo("Peak search window: " + num2str(peak_f-0.005) + " s to " + num2str(peak_f) + " s")

    String current_folder  = GetDataFolder(1)
    SVAR/Z traces_prefix   = $(ParentFolder(GetDataFolder(1), 2)+"Packages:Wave_prefix")

    String traces_folder   = current_folder + "Trace"
    String analysis_folder = current_folder + "Analysis"

    NewDataFolder/O $(analysis_folder)

    Variable analisis_status = nvar_storer("analisis_status", 1, current_folder)

    SetDataFolder(traces_folder)

    list = WaveList((traces_prefix+"*"), ";", "")
    Variable n     = ItemsInList(list)
    String stemp   = num2str(temp)
    Variable cm, tau, rs

    LogInfo("=== tempresponse START ===")
    LogInfo("Prefix: " + traces_prefix)
    LogInfo("Number of traces: " + num2str(n))

    // col 0: linear fit mode · col 1: fit near 0 mV (TODO) · col 2: no fit
    Make/O/N=(n,3) $(analysis_folder+":"+chanexp+"_fitpeak_"+stemp) = NaN
    Wave Netpeak = $(analysis_folder+":"+chanexp+"_fitpeak_"+stemp)
    Make/O/D/N=(n,3) $(analysis_folder+":"+chanexp+"_pasives_"+stemp)
    Wave pasives = $(analysis_folder+":"+chanexp+"_pasives_"+stemp)

    // Get Y axis units from first wave
    WAVE w0 = $StringFromList(0, list)
    Make/N=(numpnts(w0))/O fit
    unidadY = WaveUnits(w0, 1)
    SetScale y, 0, 1, unidadY, Netpeak

    // Label columns once, before the loop
    SetDimLabel 1, 0, pF,   pasives
    SetDimLabel 1, 1, ms,   pasives
    SetDimLabel 1, 2, MOhm, pasives

    for (i = 0; i < n; i += 1)

        WAVE w = $(StringFromList(i, list))
        String drift_name = (StringFromList(i, list)+"_drift")
        Duplicate/O w, $drift_name
        Wave drift_w = $drift_name

        // Drift subtraction: correct baseline using mean of first 10 ms
        SubtractBaseline(drift_w, 0.001, 0.011)

        // Mode 0: linear fit to first ramp segment
        Duplicate/O/FREE drift_w, fit
        CurveFit/Q/X=1 line w(t_ini+0.002, t_ini+0.042)
        Wave W_coef

        fit = W_coef[0] + W_coef[1]*x
        fit = w - fit
        Netpeak[i][0] = mean(fit, (peak_f-0.003), (peak_f-0.001))

        // Mode 1: linear fit near 0 mV (TODO)

        // Mode 2: no baseline fit
        Netpeak[i][2] = mean(drift_w, (peak_f-0.003), (peak_f-0.001))

        [cm, tau, rs] = pasivas(drift_w, 100, (peak_f+0.0006), (peak_f+0.025))
        pasives[i][0] = cm                // Cm (pF)
        pasives[i][1] = tau               // tau (ms)
        pasives[i][2] = rs                // Rs (MΩ)

        KillWaves drift_w

    endfor

    FindPeak/Q Netpeak
    if (V_flag != 0)
        LogInfo("No peaks found in Netpeak wave.")
    else
        LogInfo("Peak found: " + num2str(V_PeakVal) + " at index: " + num2str(V_PeakLoc))
    endif

    KillWaves/Z fit, W_coef, W_sigma
    SetDataFolder current_folder

    LogInfo("=== tempresponse END ===")

End


//====================================================
//   IV VISUALIZATION
//====================================================

// ------------------------------------------------------------
// Function: IV_graph
// Purpose : Plots current vs voltage from IV_Results wave.
// Inputs  : IV_Results wave in Analysis subfolder.
// Notes   : Column extraction via Extract2DColumn() (Utils).
// ------------------------------------------------------------
Function IV_graph()

    String current_folder  = GetDataFolder(1)
    String res_folder      = current_folder + "Analysis"
    String windows_name    = "IV_graph"
    Variable to

    SetDataFolder res_folder
    String IV_traces = WaveList("*IV_Results*", ";", "")

    if (ItemsInList(IV_traces) == 0)
        LogError("No IV_Results wave found in: " + res_folder)
        SetDataFolder current_folder
        return 0
    endif

    Wave IV_trace = $(res_folder + ":" + StringFromList(0, IV_traces))
    to = DimSize(IV_trace, 0)

    if (to == 0)
        LogError("IV_Results wave is empty.")
        SetDataFolder current_folder
        return 0
    endif

    // Extract 2D columns into 1D waves for plotting
    Wave xw = Extract2DColumn(IV_trace, 1, res_folder + ":IV_voltage")  // col 1 = voltage
    Wave yw = Extract2DColumn(IV_trace, 0, res_folder + ":IV_current")  // col 0 = current

    EnsureGraphWindow(windows_name, "IV curve", 200, 200, 700, 500)
    AppendToGraph/W=$windows_name yw vs xw
    ModifyGraph/W=$windows_name mode=4, marker=19, lstyle=3

    LogInfo("IV graph updated from: " + res_folder)
    SetDataFolder current_folder

End


//====================================================
//   IV ANALYSIS
//====================================================

// ------------------------------------------------------------
// Function: AnalizarIVporCanal
// Purpose : Extracts current, voltage, and passive properties
//           from an IV protocol based on square voltage pulses.
// Inputs  : Uses stored wave prefix and current experiment
//           folder structure.
// Outputs : Wave IV_Results in the Analysis subfolder.
//           Columns: [0]=current(A), [1]=voltage(V),
//                    [2]=Cm(F), [3]=tau(s), [4]=Rs(Ohm)
// Notes   : Timing and amplitude indices are hardcoded for the
//           current square-pulse protocol.
//           Drift correction via SubtractBaseline() (Common).
//           Column labels set once before the loop.
// ------------------------------------------------------------
Function AnalizarIVporCanal()

    Variable cm, tau, rs

    String currentDF     = GetDataFolder(1)
    String Swaves_prefix = (ParentFolder(GetDataFolder(1), 2)+"Packages:Wave_prefix")
    svar_check(Swaves_prefix)
    SVAR/Z traces_prefix = $Swaves_prefix

    String traces_folder   = currentDF + "Trace"
    String stim_folder     = currentDF + "Stim"
    String analysis_folder = currentDF + "Analysis"

    SetDataFolder(traces_folder)
    String Traces_list = WaveList((traces_prefix+"*"), ";", "")

    SetDataFolder(stim_folder)
    String Stim_list = WaveList((traces_prefix+"*"+"Amp"), ";", "")
    Variable n = ItemsInList(Traces_list)

    NewDataFolder/O/S $(analysis_folder)

    Make/O/N=(n,5) $(analysis_folder + ":IV_Results") = NaN
    Wave IV_res = $(analysis_folder + ":IV_Results")

    Variable i
    SetDataFolder(analysis_folder)

    LogInfo("=== AnalizarIVporCanal START ===")
    LogInfo("Number of traces: " + num2str(n))

    // Label columns once, before the loop
    SetDimLabel 1, 0, A,   IV_res
    SetDimLabel 1, 1, V,   IV_res
    SetDimLabel 1, 2, F,   IV_res
    SetDimLabel 1, 3, s,   IV_res
    SetDimLabel 1, 4, Ohm, IV_res

    for (i = 0; i < n; i += 1)

        WAVE i_trace = $(traces_folder + ":" + StringFromList(i, Traces_list))
        WAVE i_amp   = $(stim_folder   + ":" + StringFromList(i, Stim_list))

        String drift_name = (traces_folder + ":" + StringFromList(i, Traces_list) + "_drift")
        Duplicate/O i_trace, $drift_name
        Wave drift_w = $drift_name

        SubtractBaseline(drift_w, 0.001, 0.011)    // DC drift correction — first 10 ms

        [cm, tau, rs] = pasivas(drift_w, i_amp[4], (0.249+0.003), (0.249+0.006))  // hardcoded for current stimulus protocol

        IV_res[i][0] = mean(drift_w, (0.247), (0.249))  // hardcoded timing — square pulse protocol
        IV_res[i][1] = i_amp[4]                          // hardcoded amplitude index — square pulse protocol only
        IV_res[i][2] = cm
        IV_res[i][3] = tau
        IV_res[i][4] = rs

        KillWaves/Z drift_w

    endfor

    LogInfo("=== AnalizarIVporCanal END ===")
    SetDataFolder $currentDF

End
