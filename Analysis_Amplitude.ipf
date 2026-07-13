// ------------------------------------------------------------
// Function: plot_amp
// Purpose : Entry point for amplitude display. Resolves the
//           correct wave by mode and delegates to
//           MakeTwoPanels_plot_amp.
// Inputs  : mode - "raw", "norm", or "smth"
// ------------------------------------------------------------
Function plot_amp(mode)
    String mode

    String current_folder  = GetDataFolder(1)
    String analysis_folder = current_folder + "Analysis:"
    String packages_folder = current_folder + "Packages:"
    String title, y_traces, y_wave_name
    NVAR/Z temp    = $(packages_folder + "ramp_temp")
    String wbase   = "*_fitpeak_" + num2str(temp)

    SetDataFolder analysis_folder

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
        LogError("plot_amp: no waves found for mode=" + mode + " temp=" + num2str(temp))
        SetDataFolder current_folder
        return 0
    endif

    // Resolve result wave before building panel
    String mut_name = FolderNameFromPath(ParentFolder(current_folder, 4))
    mut_name = ReplaceString("'", mut_name, "")
    SVAR/Z traces_prefix = $(ParentFolder(current_folder, 3) + "Packages:Wave_prefix")
    SVAR/Z chan           = $(ParentFolder(current_folder, 1) + "Packages:chanexp")
    String maxwave_name  = mut_name + "_" + traces_prefix + "_" + chan + "_Amp"
    String amp_folder    = CheckDataFolder(ParentFolder(current_folder, 2) + "Ramp_Analysis")
    String amp_name      = amp_retreiver(maxwave_name, 6, 20, 5, amp_folder)
    Wave maxwave         = $(amp_folder + amp_name)

    Wave w = $y_wave_name
    MakeTwoPanels_plot_amp(w, title, maxwave)

    SetDataFolder current_folder
End


// ------------------------------------------------------------
// Function: MakeTwoPanels_plot_amp
// Purpose : Builds the three-subwindow amplitude panel:
//           Amp0 (fit mode 0), Amp2 (fit mode 2), Tabla_max.
//           Registers CursorMovedHook on Amp2.
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
    Duplicate/O/R=[][0] w w_col0
    Duplicate/O/R=[][2] w w_col2

    // Store cursor wave path — must use name-based convention
    // because CsrWave() is unreliable in hosted subgraphs.
    StoreCursorWavePath("Fig1", w_col2)

    if (WinType("Fig1"))
        KillWindow/Z Fig1
    endif

    NewPanel/K=1/W=(753,442,2063,842) as title
    DoWindow/C Fig1

    DrawText 180, 30, "Fit mode 0"
    DrawText 545, 30, "Fit mode 2"

    Display/HOST=Fig1/N=Amp0/W=(10,50,410,350)   w_col0
    Display/HOST=Fig1/N=Amp2/W=(430,50,830,350)  w_col2
    Edit/HOST=Fig1/K=1/N=Tabla_max/W=(850,50,1300,350) maxwave.id

    // Cursor placement — string name required for hosted subgraphs
    String w_col2_name = NameOfWave(w_col2)
    Variable x_range   = rightx(w_col2) - leftx(w_col2)
    Cursor/H=2/L=1/W=Fig1#Amp2 A, $w_col2_name, leftx(w_col2) + x_range * 0.1
    Cursor/H=2/L=1/W=Fig1#Amp2 B, $w_col2_name, leftx(w_col2) + x_range * 0.9

    DoUpdate
    ShowInfo/W=Fig1
    SetWindow Fig1#Amp2, hook(cursor)=CursorMovedHook

    Button store_amp, pos={1139,361}, size={100,20}, title="Store amp", proc=AmpButtonProc
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

    findamp(w, x_a, x_b)
End


// ------------------------------------------------------------
// Function: findamp
// Purpose : Calculates amplitude values from cursor positions
//           and passes them to amp_saver. Resolves experiment
//           context (mut_name, prefix, chan, temp, folder).
// Inputs  : w   - active wave (col2 of fitpeak)
//           x_a - X position of cursor A (baseline)
//           x_b - X position of cursor B (peak search end)
// ------------------------------------------------------------
Function findamp(w, x_a, x_b)
    Wave w
    Variable x_a, x_b

    Variable amp_ini = w(x_a)
    Variable max_val = WaveMax(w, min(x_a, x_b), max(x_a, x_b))

    String current_folder = GetDataFolder(1)
    SetDataFolder $(current_folder + "Packages")

    SVAR/Z chan         = chanexp
    NVAR/Z temp         = ramp_temp
    SVAR/Z traces_prefix = $(ParentFolder(GetDataFolder(1), 3) + "Packages:Wave_prefix")

    String mut_name = FolderNameFromPath(ParentFolder(GetDataFolder(1), 4))
    mut_name = ReplaceString("'", mut_name, "")

    String amp_folder = CheckDataFolder(ParentFolder(current_folder, 2) + "Ramp_Analysis")

    nvar_storer("amp_ini", amp_ini, current_folder)
    nvar_storer("amp_fin", max_val, current_folder)

    SetDataFolder current_folder

    amp_saver(mut_name, traces_prefix, chan, amp_ini,             0, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, max_val,             1, temp, amp_folder)
    amp_saver(mut_name, traces_prefix, chan, (max_val - amp_ini), 2, temp, amp_folder)
End


// ------------------------------------------------------------
// Function: amp_saver
// Purpose : Writes a scalar amplitude value into the result
//           wave at the correct temperature row and column.
// Inputs  : mut_name      - mutant/experiment label
//           traces_prefix - wave prefix string
//           chan          - channel name
//           max_amp       - value to store
//           col_index     - column (0=ini, 1=peak, 2=delta)
//           temp          - temperature (°C)
//           amp_folder    - full path to Ramp_Analysis folder
//                           (with trailing ":")
// Notes   : nT, t0, dt hardcoded — TODO read from Packages.
//           Does not resolve folder paths — caller's responsibility.
// ------------------------------------------------------------
Function amp_saver(mut_name, traces_prefix, chan, max_amp, col_index, temp, amp_folder)
    String mut_name, traces_prefix, chan, amp_folder
    Variable max_amp, col_index, temp

    Variable nT  = 6
    Variable t0  = 20
    Variable dt  = 5
    Variable idx = round((temp - t0) / dt)

    if (idx < 0 || idx >= nT)
        LogError("amp_saver: idx out of range: " + num2str(idx) + " temp=" + num2str(temp))
        return 0
    endif
    if (col_index < 0 || col_index >= 3)
        LogError("amp_saver: col_index out of range: " + num2str(col_index))
        return 0
    endif

    String maxwave_name = mut_name + "_" + traces_prefix + "_" + chan + "_Amp"
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
// Notes   : nT, t0, dt hardcoded at call sites — TODO refactor
//           to read from Packages globals before publication.
// ------------------------------------------------------------
Function/S amp_retreiver(maxwave_name, nT, t0, dt, target_folder)
    String maxwave_name, target_folder
    Variable nT, t0, dt

    String full_path = target_folder + maxwave_name

    if (!WaveExists($full_path))
        Make/O/N=(nT, 3) $full_path
        Wave maxwave = $full_path
        maxwave = NaN
        SetScale/P x, t0, dt, "°C", maxwave
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