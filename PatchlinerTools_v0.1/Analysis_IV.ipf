#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

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
//           Drift correction via SubtractBaseline() (Utils).
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


//====================================================
//   IV GRAPHS
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

    // Validate and load IV_Results wave
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


// ------------------------------------------------------------
// Function: plot_stim
// Purpose : Plots stimulus waves (Amp vs Dur) from Stim folder.
//           Places cursors at 30% and 70% of x range.
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
        LogError("No stimulus waves found in: " + stim_folder)
        return 0
    endif

    EnsureGraphWindow(win_name, "Stimulus", 200, 200, 700, 500)
    AppendXYWaveListToGraph(win_name, amp_list, dur_list, stim_folder)

    // Place cursors on last appended trace
    Wave yw_last     = $(stim_folder + StringFromList(n-1, amp_list))
    String last_name = StringFromList(n-1, amp_list)
    Variable x_range = rightx(yw_last) - leftx(yw_last)
    Cursor/H=2/L=1/W=$win_name A, $last_name, leftx(yw_last) + x_range * 0.3
    Cursor/H=2/L=1/W=$win_name B, $last_name, leftx(yw_last) + x_range * 0.7
    ShowInfo/W=$win_name

    StoreCursorWavePath(win_name, yw_last)
    LogInfo("Stimulus waves appended from: " + stim_folder)
End


// ------------------------------------------------------------
// Function: plot_trace
// Purpose : Plots all trace waves from the Trace subfolder.
// ------------------------------------------------------------
Function plot_trace()

    String current_folder = GetDataFolder(1)
    String trace_folder   = current_folder + "Trace:"
    String win_name       = "trace_graph"
    Variable level        = 2

    String parent = ParentFolder(current_folder, level)
    SVAR/Z w_prefix = $(parent+"Packages:"+"Wave_prefix")

    SetDataFolder trace_folder
    String y_traces = WaveList((w_prefix+"*"), ";", "")
    SetDataFolder current_folder

    Variable n = ItemsInList(y_traces)
    if (n == 0)
        LogError("No trace waves found in: " + trace_folder)
        return 0
    endif

    EnsureGraphWindow(win_name, "Raw traces", 200, 200, 700, 500)
    AppendWaveListToGraph(win_name, y_traces, trace_folder)

    LogInfo("Trace waves appended from: " + trace_folder)
End



// ------------------------------------------------------------
// Function: plot_raw_panel
// Purpose : Displays raw current traces (Trace/) and stimulus
//           waveforms (Stim/) stacked vertically in a hosted
//           panel, so X axes are aligned.
//           Top subgraph:    current traces (Y only).
//           Bottom subgraph: stimulus amplitude vs duration (XY).
//           Cursors A/B are placed on the stimulus subgraph.
// Inputs  : none — operates on the current data folder:
//             <exp_folder>:Trace/  — current wave traces
//             <exp_folder>:Stim/   — _Amp and _Dur waves
// Outputs : none (side-effect: panel "RawPanel" created/updated)
// Notes   : Requires Wave_prefix two levels up in Packages.
//           CsrWave() does not work with hosted subgraphs ("#"),
//           so the active wave path is stored via
//           StoreCursorWavePath as root:Packages:RawPanel_wave_path.
// ------------------------------------------------------------
Function plot_raw_panel()

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

    // Axis labels — suppress bottom axis on Traces to avoid duplication
    Label/W=$(panel_name+"#Traces") left   "Current"
    Label/W=$(panel_name+"#Traces") bottom "Time (s)"
    Label/W=$(panel_name+"#Stim")   left   "Amplitude"
    Label/W=$(panel_name+"#Stim")   bottom "Time (s)"

    // Cursors on stimulus subgraph
    // CsrWave() does not work with hosted "#" subgraphs.
    // Wave path stored in root:Packages for CursorMovedHook.
    Wave stim_last        = $(stim_folder + StringFromList(nStim-1, amp_list))
    String stim_last_name = StringFromList(nStim-1, amp_list)
    String stim_win       = panel_name + "#Stim"

    Variable x_range = rightx(stim_last) - leftx(stim_last)
    Cursor/H=2/L=1/W=$stim_win A, $stim_last_name, leftx(stim_last) + x_range * 0.3
    Cursor/H=2/L=1/W=$stim_win B, $stim_last_name, leftx(stim_last) + x_range * 0.7

    StoreCursorWavePath(panel_name, stim_last)

    ShowInfo/W=$panel_name

    LogInfo("plot_raw_panel: " + num2str(nTrace) + " traces, " + num2str(nStim) + " stim pairs appended.")
End
