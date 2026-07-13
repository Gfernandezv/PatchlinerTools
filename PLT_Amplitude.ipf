#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

// ------------------------------------------------------------
// Function: plot_amp_analysis
// Purpose : Entry point for amplitude display. Resolves the
//           correct wave by mode, resolves experiment context
//           (mut_name, traces_prefix, chan, amp_folder), and
//           delegates to MakeTwoPanels_plot_amp.
// Inputs  : mode - "raw", "norm", or "smth"
// Notes   : Path resolution done here per R4 — helpers receive
//           folder paths as parameters, no internal resolution.
// ------------------------------------------------------------
Function plot_amp_analysis(mode)
    String mode
	 
    String current_folder  = GetDataFolder(1)
    String analysis_folder = current_folder + "Analysis:"
    String packages_folder = current_folder + "Packages:"
    String title, y_traces, y_wave_name
    NVAR/Z temp    = $(packages_folder + "ramp_temp")
    String wbase   = "*_fitpeak_" + num2str(temp)

 
    SetDataFolder $analysis_folder

    strswitch(mode)
        case "raw":
            y_traces    = WaveList(wbase, ";", "")
            title       = "Raw graphs"
            break
        case "norm":
            y_traces    = WaveList(wbase + "_norm", ";", "")
            title       = "Norm graphs"
            break
        case "smth":
            y_traces    = WaveList(wbase + "_norm_smth", ";", "")
            title       = "Smooth graphs"
            break
    endswitch

    y_wave_name = StringFromList(0, y_traces)
    if (strlen(y_wave_name) == 0)
        LogError("plot_amp_analysis: no waves found for mode=" + mode + " temp=" + num2str(temp))
        SetDataFolder current_folder
        return 0
    endif

    // Resolve result wave before building panel
    String mut_name = FolderNameFromPath(ParentFolder(current_folder, 3))
    mut_name = ReplaceString("'", mut_name, "")
    SVAR/Z traces_prefix = $(ParentFolder(current_folder, 2) + "Packages:Wave_prefix")
    SVAR/Z chan           = $(ParentFolder(current_folder, 0) + "Packages:chanexp")
    String maxwave_name  = "'"+mut_name + "_" + traces_prefix + "_" + chan + "_Amp'"

    String amp_folder    = CheckDataFolder(ParentFolder(current_folder, 2) + "Ramp_Analysis")
    // Read temperature grid from Packages globals; fall back to defaults
    Variable nT = NumVarOrDefault("root:Packages:amp_nT", 6)
    Variable t0 = NumVarOrDefault("root:Packages:amp_t0", 20)
    Variable dt = NumVarOrDefault("root:Packages:amp_dt", 5)
    String amp_name = amp_retreiver(maxwave_name, nT, t0, dt, amp_folder)
    Wave maxwave         = $(amp_folder + amp_name)
	 
	 
    Wave w = $y_wave_name

    MakeTwoPanels_plot_amp(w, title, maxwave)

	 SetDataFolder $current_folder
End


// ------------------------------------------------------------
// Function: MakeTwoPanels_plot_amp
// Purpose : Builds the three-subwindow amplitude panel:
//           Amp0 (fit mode 0), Amp2 (fit mode 2), Tabla_max.
//           Registers CursorMovedHook on Amp2.
// 			 works with the Analysis folder selected
// Inputs  : w       - 2D wave with columns [0]=mode0, [2]=mode2
//           title   - panel display title
//           maxwave - pre-resolved result wave for Tabla_max
// Notes   : Caller is responsible for resolving maxwave before
//           calling this function.
// ------------------------------------------------------------
Function MakeTwoPanels_plot_amp(w, title, maxwave)
    Wave w, maxwave
    String title

    // Extract columns in current folder
    Duplicate/O/R=[][2] w w_col2

    // Store cursor wave path — must use name-based convention
    // because CsrWave() is unreliable in hosted subgraphs.
    StoreCursorWavePath("Fig1", w_col2)

    if (WinType("Fig1"))
        KillWindow/Z Fig1
    endif

    NewPanel/K=1/W=(753,442,2000,842) as title
    DoWindow/C Fig1

    DrawText 180, 30, "Fit mode 2"

    Display/HOST=Fig1/N=Amp2/W=(10,50,410,350) w_col2
    ModifyGraph/W=Fig1#Amp2 mode(w_col2)=4, marker(w_col2)=19

    Variable nPts = numpnts(w_col2)
    LoadCividis()
    Make/O/N=(nPts) root:Packages:ColorTables:Misc:cividis_zwave
    Wave cividis_zwave = root:Packages:ColorTables:Misc:cividis_zwave
    cividis_zwave = p
    ModifyGraph/W=Fig1#Amp2 zColor(w_col2)={cividis_zwave,0,nPts-1,Rainbow,0}

    Edit/HOST=Fig1/K=1/N=Tabla_max/W=(430,50,870,350) maxwave.ld
    ModifyTable/W=Fig1#Tabla_max font="Arial", size=10, showParts=0x04

    Display/HOST=Fig1/N=curve1/W=(900,50,1300,190)  maxwave[][%Amplitude]   vs maxwave[][%Temp]
    ModifyGraph/W=Fig1#curve1 mode=4, marker=8, msize=3, opaque=1, lstyle=3, rgb=(65535,0,0,32768), useMrkStrokeRGB=1

    Display/HOST=Fig1/N=curve2/W=(900,210,1300,350) maxwave[][%lnAmplitude] vs maxwave[][%invtemp]
    Label/W=Fig1#curve2 left   "ln I0/Imax"
    Label/W=Fig1#curve2 bottom "1/T (1/°K)"
    ModifyGraph/W=Fig1#curve2 mode=4, marker=8, msize=3, opaque=1, lstyle=3, rgb=(65535,0,0,32768), useMrkStrokeRGB=1
	 
    // Cursor placement via shared helper
    place_cursors("Fig1#Amp2", w_col2, 0.1, 0.9)

    DoUpdate
    ShowInfo/W=Fig1
    SetWindow Fig1#Amp2, hook(cursor)=CursorMovedHook

    Button store_amp, pos={700,361}, size={100,20}, title="Store amp", proc=AmpButtonProc
End



// ------------------------------------------------------------
// Function: AmpButtonProc
// Purpose : Reads cursor positions from Fig1#Amp2 and calls
//           findamp() with the active wave and cursor X values.
// ------------------------------------------------------------
Function AmpButtonProc(ctrlName) : ButtonControl
    String ctrlName

    Variable x_a = xcsr(A, "Fig1#Amp2")
    Variable x_b = xcsr(B, "Fig1#Amp2")

    if (numtype(x_a) == 2 || numtype(x_b) == 2)
        LogWarn("AmpButtonProc: cursors not set on Fig1#Amp2")
        return 0
    endif

    SVAR/Z path = root:Packages:Fig1_wave_path
    if (!SVAR_Exists(path))
        LogError("AmpButtonProc: Fig1_wave_path not found in root:Packages")
        return 0
    endif

    Wave/Z w = $path
    if (!WaveExists(w))
        LogError("AmpButtonProc: wave not found at path: " + path)
        return 0
    endif

    // Resolve experiment context here (R4) before calling findamp
    String wave_folder = GetWavesDataFolder(w, 1)
    String exp_folder  = ParentFolder(wave_folder, 1)

    SVAR/Z chan          = $(exp_folder + "Packages:chanexp")
    NVAR/Z temp          = $(exp_folder + "Packages:ramp_temp")
    SVAR/Z traces_prefix = $(ParentFolder(exp_folder, 1) + "Packages:Wave_prefix")

    String mut_name  = FolderNameFromPath(ParentFolder(exp_folder, 2))
    mut_name         = ReplaceString("'", mut_name, "")
    String amp_folder = CheckDataFolder(ParentFolder(exp_folder, 1) + "Ramp_Analysis")

    findamp(w, x_a, x_b, mut_name, traces_prefix, chan, temp, amp_folder)
End


// ------------------------------------------------------------
// Function: findamp
// Purpose : Calculates amplitude values from cursor positions
//           and passes them to amp_saver.
//           Experiment context (mut_name, prefix, chan, temp,
//           amp_folder) is resolved by the caller
//           (plot_amp_analysis) and passed as parameters.
// Inputs  : w             - active wave (col2 of fitpeak)
//           x_a           - X position of cursor A (baseline)
//           x_b           - X position of cursor B (peak search end)
//           mut_name      - mutant/experiment label
//           traces_prefix - wave prefix string
//           chan          - channel name
//           temp          - temperature (°C)
//           amp_folder    - full path to Ramp_Analysis folder
// ------------------------------------------------------------
Function findamp(w, x_a, x_b, mut_name, traces_prefix, chan, temp, amp_folder)
    Wave w
    Variable x_a, x_b, temp
    String mut_name, traces_prefix, chan, amp_folder

    Variable amp_ini = w(x_a)
    Variable max_val = WaveMax(w, min(x_a, x_b), max(x_a, x_b))

    String current_folder = GetDataFolder(1)
    nvar_storer("amp_ini",    amp_ini,             current_folder)
    nvar_storer("amp_fin",    max_val,             current_folder)
    nvar_storer("amp_netamp", (max_val - amp_ini), current_folder)

    amp_saver(mut_name, traces_prefix, chan, (273.15+temp),        0, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, amp_ini,              1, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, max_val,              2, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, (max_val - amp_ini),  3, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, ln(max_val - amp_ini),4, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, 1/(273.15+temp),      5, temp, amp_folder)
End


// ------------------------------------------------------------
// Function: amp_saver
// Purpose : Writes a scalar amplitude value into the result
//           wave at the correct temperature row and column.
// Inputs  : mut_name      - mutant/experiment label
//           traces_prefix - wave prefix string
//           chan          - channel name
//           max_amp       - value to store
//           col_index     - column (0=Temp, 1=Ini, 2=Peak,
//                           3=Amplitude, 4=lnAmplitude, 5=invtemp)
//           temp          - temperature (°C)
//           amp_folder    - full path to Ramp_Analysis folder
//                           (with trailing ":")
// Notes   : nT, t0, dt read from Packages globals if available;
//           fall back to defaults (6, 20, 5) if not set.
//           Does not resolve folder paths — caller's responsibility.
// ------------------------------------------------------------
Function amp_saver(mut_name, traces_prefix, chan, max_amp, col_index, temp, amp_folder)
    String mut_name, traces_prefix, chan, amp_folder
    Variable max_amp, col_index, temp

    // Read temperature grid from Packages globals; fall back to defaults
    Variable nT  = NumVarOrDefault("root:Packages:amp_nT", 6)
    Variable t0  = NumVarOrDefault("root:Packages:amp_t0", 20)
    Variable dt  = NumVarOrDefault("root:Packages:amp_dt", 5)
    Variable idx = round((temp - t0) / dt)

    if (idx < 0 || idx >= nT)
        LogError("amp_saver: idx out of range: " + num2str(idx) + " temp=" + num2str(temp))
        return 0
    endif
    if (col_index < 0 || col_index >= 6)
        LogError("amp_saver: col_index out of range: " + num2str(col_index))
        return 0
    endif

    String maxwave_name = "'"+mut_name + "_" + traces_prefix + "_" + chan + "_Amp'"
    String full_path    = amp_folder + maxwave_name

    Wave maxwave = $full_path
    if (!WaveExists(maxwave))
        amp_retreiver(maxwave_name, nT, t0, dt, amp_folder)
        Wave maxwave = $full_path
    endif

    maxwave[idx][col_index] = max_amp
    LogInfo("amp_saver: " + NameOfWave(maxwave) + \
            " idx:"       + num2str(idx)         + \
            " col:"       + num2str(col_index)   + \
            " value:"     + num2str(max_amp))
End


// ------------------------------------------------------------
// Function: amp_retreiver
// Purpose : Creates and initializes the amplitude result wave
//           in the target folder if it does not already exist.
// Inputs  : maxwave_name  - wave name without quotes or path
//           nT            - number of temperature points
//           t0            - first temperature (°C)
//           dt            - temperature step (°C)
//           target_folder - full folder path (with trailing ":")
// Outputs : wave name without path (String)
// Notes   : nT, t0, dt read from Packages globals by amp_saver;
//           passed explicitly here so amp_retreiver remains a
//           pure initialization helper with no folder resolution.
// ------------------------------------------------------------
Function/S amp_retreiver(maxwave_name, nT, t0, dt, target_folder)
    String maxwave_name, target_folder
    Variable nT, t0, dt

    String full_path = target_folder + maxwave_name

    if (!WaveExists($full_path))
        Make/O/N=(nT, 6) $full_path
        Wave maxwave = $full_path
        maxwave = NaN
        SetScale/P x, t0, dt, "°K", maxwave
        SetDimLabel 1, 0, Temp, maxwave
        SetDimLabel 1, 1, Ini,   maxwave
	     SetDimLabel 1, 2, Peak,  maxwave
		  SetDimLabel 1, 3, Amplitude, maxwave
		  SetDimLabel 1, 4, lnAmplitude, maxwave
		  SetDimLabel 1, 5, invtemp, maxwave
    endif

    return maxwave_name
End


// ------------------------------------------------------------
// Function: CursorMovedHook
// Purpose : Updates the reference line in Fig1#Amp2 when
//           cursors A or B move.
// ------------------------------------------------------------
Function CursorMovedHook(info)
    String info

    String win_name = StringByKey("GRAPH", info, ":", ";")
    if (!stringmatch(win_name, "Amp2"))
        return 0
    endif

    SVAR/Z path = root:Packages:Fig1_wave_path
    if (!SVAR_Exists(path))
        return 0
    endif
    Wave/Z w_col2 = $path
    if (!WaveExists(w_col2))
        return 0
    endif

    Variable x_a = xcsr(A, "Fig1#Amp2")
    Variable x_b = xcsr(B, "Fig1#Amp2")
    if (numtype(x_a) == 2 || numtype(x_b) == 2)
        return 0
    endif

    Variable maxVal = WaveMax(w_col2, min(x_a, x_b), max(x_a, x_b))

    // Update reference line
    String ref_path = GetWavesDataFolder(w_col2, 1) + "ref_line"
    Make/O/N=2 $ref_path
    Wave ref_line = $ref_path
    ref_line = maxVal
    SetScale/I x, min(x_a, x_b), max(x_a, x_b), ref_line

    String traceList = TraceNameList("Fig1#Amp2", ";", 1)
    if (strsearch(traceList, "ref_line", 0) < 0)
        AppendToGraph/W=Fig1#Amp2 ref_line
        ModifyGraph/W=Fig1#Amp2 lstyle(ref_line)=3, rgb(ref_line)=(0,0,65535)
    endif

    LogInfo("CursorMovedHook: max=" + num2str(maxVal))
End