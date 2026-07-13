#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

//====================================================
//   LOGGER
//====================================================

Function InitLogger()
    DFREF dfr = root:logging

    if (DataFolderRefStatus(dfr) == 0)
        NewDataFolder/O root:logging
    endif

    Wave/T/Z w = root:logging:messages
    if (!WaveExists(w))
        Make/O/T/N=0 root:logging:messages
    endif
End

Function LogMessage(msg, level)
    String msg, level

    InitLogger()
    Wave/T w = root:logging:messages

    InsertPoints numpnts(w), 1, w
    w[numpnts(w)-1] = date() + " " + time() + "\t[" + level + "] " + msg
End

Function LogInfo(msg)
    String msg
    LogMessage(msg, "INFO")
End

Function LogWarn(msg)
    String msg
    LogMessage(msg, "WARN")
End

Function LogError(msg)
    String msg
    LogMessage(msg, "ERROR")
End


//====================================================
//   LOG CONSOLE PANEL
//====================================================

Window LogConsole() : Panel
    PauseUpdate; Silent 1

    InitLogger()

    NewPanel/K=1/W=(1845,1000,2545,1420) as "Log console"

    ListBox logList, pos={10,10}, size={530,300}
    ListBox logList, listWave=root:logging:messages
    ListBox logList, mode=1, selRow=-1

    Button btnSave,  pos={10,320},  size={90,22}, title="Save log", proc=LogButtonProc
    Button btnClear, pos={110,320}, size={90,22}, title="Clear",    proc=LogButtonProc
    Button btnClose, pos={210,320}, size={90,22}, title="Close",    proc=LogButtonProc
End

//====================================================
//   Buttons controlers
//====================================================

Function LogButtonProc(ctrlName) : ButtonControl
    String ctrlName

    strswitch(ctrlName)

        case "btnSave":
            PathInfo home
            String fname = "igor_log_" + ReplaceString(":", time(), "-") + ".txt"
            Save/T root:logging:messages as (S_path + fname)
            LogInfo("Log saved to: " + S_path + fname)
            break

        case "btnClear":
            Redimension/N=0 root:logging:messages
            LogInfo("Log cleared.")
            break

        case "btnClose":
            DoWindow/K LogConsole
            break

        case "btnorder":
            prefix_detector()
            break

        case "btnStim":
            plot_raw_panel(1)
            //plot_stim()
            break

        case "btnRamp":
            menu_tempresponse()
            break

        case "btnplotamp":
            plot_amp_analysis("raw")
            break

        case "btnIV":
        		//plot_ampIV("raw")
            //AnalizarIVporCanal()
            break

        case "btnIVgraph":
            IV_graph()
            break

    endswitch

    return 0
End


//====================================================
//   GLOBAL VARIABLE HELPERS
//====================================================

// ------------------------------------------------------------
// Function: nvar_storer
// Purpose : Stores or retrieves a global numeric variable
//           in the Packages subfolder of the given folder.
// Inputs  : var_name  - variable name
//           var_value - NaN to retrieve; any number to store
//           folder    - target data folder path
// Outputs : stored or retrieved value
// Notes   : If variable does not exist in retrieve mode,
//           prompts the user to enter a value.
// ------------------------------------------------------------
Function nvar_storer(var_name, var_value, folder)
    String var_name
    Variable var_value
    String folder

    NewDataFolder/O $(folder+"Packages")
    String path_tovar = folder + "Packages:" + var_name

    Variable nVal

    if (numtype(var_value) == 2)    // NaN → retrieve mode
        nVal = NumVarOrDefault(path_tovar, NaN)
        if (numtype(nVal) == 2)     // variable doesn't exist → ask user
            Prompt nVal, (var_name + " not set, enter value:")
            DoPrompt "Missing variable", nVal
        endif
    else                            // store mode
        Variable/G $(path_tovar) = var_value
        nVal = var_value
    endif

    return nVal
End

// ------------------------------------------------------------
// Function: svar_storer
// Purpose : Stores or retrieves a global string variable
//           in the Packages subfolder of the given folder.
// ------------------------------------------------------------
Function/S svar_storer(var_name, var_value, folder)
    String var_name, var_value, folder

    String path_tovar = folder + "Packages:" + var_name
    NewDataFolder/O $(folder+"Packages")

    SVAR/Z old = $(path_tovar)
    String oldVal

    if (SVAR_Exists(old))
        oldVal = old
    else
        oldVal = "Null"
    endif

    String/G $(path_tovar) = var_value
    oldVal = var_value

    return oldVal
End

// ------------------------------------------------------------
// Function: svar_check
// Purpose : Verifies that a global string variable exists.
// Inputs  : ask - full path to the string variable
// ------------------------------------------------------------
Function svar_check(ask)
    String ask
    SVAR asking = $ask
    if (!SVAR_Exists(asking))
        LogError("Wave_prefix not found: " + ask)
        return 0
    endif
End


//====================================================
//   FOLDER PATH HELPERS
//====================================================

// ------------------------------------------------------------
// Function: ParentFolder
// Purpose : Returns the parent folder path at a given level
//           above the current path.
// Inputs  : path  - data folder path (with trailing ":")
//           level - number of levels to go up
// ------------------------------------------------------------
Function/S ParentFolder(path, level)
    String path
    Variable level

    String noEnd = RemoveEnding(path, ":")

    Variable n = ItemsInList(noEnd, ":")
    if (n <= 1)
        return "root:"
    endif

    String out = ""
    Variable i
    for (i = 0; i < n-level; i += 1)
        out += StringFromList(i, noEnd, ":") + ":"
    endfor

    return out
End

// ------------------------------------------------------------
// Function: FolderNameFromPath
// Purpose : Extracts the last folder name from a full path.
// ------------------------------------------------------------
Function/S FolderNameFromPath(path)
    String path
    String p = RemoveEnding(path, ":")
    Variable n = ItemsInList(p, ":")
    return StringFromList(n-1, p, ":")
End


//====================================================
//   WAVE UTILITIES
//====================================================

// ------------------------------------------------------------
// Function: SubtractBaseline
// Purpose : Subtracts the mean of a baseline window from a wave
//           in-place. Used for DC drift correction before
//           analysis.
// Inputs  : w    - wave to correct (modified in place)
//           t0   - baseline window start (s)
//           t1   - baseline window end (s)
// Outputs : baseline value subtracted (Variable)
// Notes   : Baseline = mean(w[t0 .. t1]).
//           By convention, Nanion Patchliner protocols use
//           [0.001, 0.011] s (first 10 ms) as the baseline
//           window in both tempresponse() and
//           AnalizarIVporCanal().
// ------------------------------------------------------------
Function SubtractBaseline(w, t0, t1)
    Wave w
    Variable t0, t1

    Variable baseline = mean(w, t0, t1)
    w -= baseline
    return baseline
End


// ------------------------------------------------------------
// Function: ListSubfolders
// Purpose : Returns a semicolon-separated list of subfolder
//           names that start with a given prefix, found in
//           the specified parent folder.
// Inputs  : parent_path - full folder path (with ":")
//           name_prefix - filter prefix (e.g. "chan_", "exp_")
// Outputs : semicolon-separated list of matching folder names
// Notes   : Generic helper — no domain-specific logic.
//           Parses DataFolderDir(1) output.
//           Assumes folder names contain no commas or spaces,
//           consistent with the chan_X / exp_Y naming convention.
//           Used by second_phase() (Common) and
//           NMExport_CopyWaves() (NMExport).
// ------------------------------------------------------------
Function/S ListSubfolders(parent_path, name_prefix)
    String parent_path, name_prefix

    String saved_folder = GetDataFolder(1)
    SetDataFolder $parent_path

    // DataFolderDir(1) format: "FOLDERS:f1,f2,...;WAVES:...;"
    String dir_str    = DataFolderDir(1)
    String folder_str = StringFromList(0, StringFromList(1, dir_str, ":"), ";")
    Variable n        = ItemsInList(folder_str, ",")
    String result     = ""
    Variable i

    for (i = 0; i < n; i += 1)
        String fname = TrimString(StringFromList(i, folder_str, ","))
        if (stringmatch(fname, name_prefix + "*"))
            result += fname + ";"
        endif
    endfor

    SetDataFolder $saved_folder
    return result
End

// ------------------------------------------------------------
// Function: Extract2DColumn
// Purpose : Extracts a single column from a 2D wave into a new
//           1D wave at the specified full path.
// Inputs  : src       - source 2D wave
//           col       - column index to extract
//           dest_path - full destination path (folder:wavename)
// Outputs : reference to the created/overwritten wave
// Notes   : Generic helper — no electrophysiology domain logic.
//           Replaces the manual Make/O + loop pattern used in
//           IV_graph() and similar plotting functions.
// ------------------------------------------------------------
Function/WAVE Extract2DColumn(src, col, dest_path)
    Wave src
    Variable col
    String dest_path

    Variable n = DimSize(src, 0)
    Make/O/N=(n) $dest_path
    Wave dest = $dest_path
    dest[] = src[p][col]
    return dest
End


//====================================================
//   GRAPH UTILITIES
//====================================================

// ------------------------------------------------------------
// Function: place_cursors
// Purpose : Places cursors A and B at relative positions
//           within a graph window on a given wave.
// Inputs  : win_name  - target graph window name
//           w         - wave to place cursors on
//           pos_a     - relative position of cursor A (0-1)
//           pos_b     - relative position of cursor B (0-1)
// Notes   : Cursors are horizontal (H=2), style 1.
//           Uses wave name as string (not wave reference) for
//           compatibility with hosted subgraphs ("#" syntax).
//           CsrWave() is unreliable in hosted subgraphs — use
//           StoreCursorWavePath() after calling this function.
// ------------------------------------------------------------
Function place_cursors(win_name, w, pos_a, pos_b)
    String win_name
    Wave w
    Variable pos_a, pos_b

    place_cursor(win_name, w, "A", pos_a)
    place_cursor(win_name, w, "B", pos_b)
End

// ------------------------------------------------------------
// Function: place_cursor
// Purpose : Places a single cursor at a relative position
//           within a graph window on a given wave.
// Inputs  : win_name   - target graph window name
//           w          - wave to place cursor on
//           csr_name   - cursor name ("A", "B", "C", etc.)
//           pos        - relative position (0–1)
// Notes   : Cursor is horizontal (H=2), style 1.
//           Compatible with hosted subgraphs ("#" syntax).
//           Call StoreCursorWavePath() after placing cursors
//           for hook-based access.
// ------------------------------------------------------------
Function place_cursor(win_name, w, csr_name, pos)
    String win_name, csr_name
    Wave w
    Variable pos

    Variable x_pos    = leftx(w) + (rightx(w) - leftx(w)) * pos
    String trace_name = NameOfWave(w)

    Cursor/H=2/L=1/W=$win_name $csr_name, $trace_name, x_pos
End

// ------------------------------------------------------------
// Function: StoreCursorWavePath
// Purpose : Stores the full path of the wave used as cursor
//           target in root:Packages:[graph_name]_wave_path.
//           Required because CsrWave() does not work reliably
//           with hosted subgraphs (# syntax).
// Inputs  : graph_name - base graph name (no "#subgraph" suffix)
//           w          - wave on which cursors are placed
// Outputs : none (side-effect: string global created/updated)
// Notes   : Project-wide convention — every graph using cursors
//           for analysis stores its active wave path here.
//           Path obtained via GetWavesDataFolder(w, 2).
// ------------------------------------------------------------
Function StoreCursorWavePath(graph_name, w)
    String graph_name
    Wave w

    NewDataFolder/O root:Packages
    String var_path = "root:Packages:" + graph_name + "_wave_path"
    String/G $(var_path) = GetWavesDataFolder(w, 2)
End


//====================================================
//   GRAPH WINDOW HELPERS
//====================================================

// ------------------------------------------------------------
// Function: EnsureGraphWindow
// Purpose : Creates a plain graph window if it does not exist;
//           brings it to front otherwise.
// Inputs  : win_name        - internal window name (no spaces)
//           title           - display title string
//           lft, top, rgt, bot - window coordinates (pixels)
// Outputs : none (side-effect: window exists and is in front)
// Notes   : Avoids repeating the WinType/DoWindow/F pattern
//           across all plotting functions.
// ------------------------------------------------------------
Function EnsureGraphWindow(win_name, title, lft, top, rgt, bot)
    String win_name, title
    Variable lft, top, rgt, bot

    if (!WinType(win_name))
        Display/K=1/N=$win_name/W=(lft,top,rgt,bot) as title
    else
        DoWindow/F $win_name
    endif
End


// ------------------------------------------------------------
// Function: AppendWaveListToGraph
// Purpose : Appends all waves in a semicolon-separated list
//           to a graph window (Y-only, no X wave).
// Inputs  : win_name - target graph window name
//           wList    - semicolon-separated list of wave names
//           folder   - full data folder path (with trailing ":")
// Outputs : number of waves appended (Variable)
// Notes   : Wave names in wList must not include the folder path.
//           Does not handle XY pairs; use AppendXYWaveListToGraph.
// ------------------------------------------------------------
Function AppendWaveListToGraph(win_name, wList, folder)
    String win_name, wList, folder
    Variable i, n

    n = ItemsInList(wList)
    for (i = 0; i < n; i += 1)
        Wave w = $(folder + StringFromList(i, wList))
        AppendToGraph/W=$win_name w
    endfor

    return n
End


// ------------------------------------------------------------
// Function: AppendXYWaveListToGraph
// Purpose : Appends matched XY wave pairs (y vs x) to a graph.
// Inputs  : win_name - target graph window name
//           yList    - semicolon list of Y wave names
//           xList    - semicolon list of X wave names (same order)
//           folder   - full data folder path (with trailing ":")
// Outputs : number of pairs appended (Variable)
// Notes   : Mismatched list lengths are silently truncated to
//           the shorter one.
// ------------------------------------------------------------
Function AppendXYWaveListToGraph(win_name, yList, xList, folder)
    String win_name, yList, xList, folder
    Variable i, n

    n = min(ItemsInList(yList), ItemsInList(xList))
    for (i = 0; i < n; i += 1)
        Wave yw = $(folder + StringFromList(i, yList))
        Wave xw = $(folder + StringFromList(i, xList))
        AppendToGraph/W=$win_name yw vs xw
    endfor

    return n
End

// ------------------------------------------------------------
// Function: CheckDataFolder
// Purpose : Verifies that a data folder exists; creates it if
//           missing. Logs both events.
// Inputs  : path - full folder path (without trailing ":")
// Outputs : path with trailing ":" (String)
// Notes   : Only creates the terminal folder level. For nested
//           paths use EnsureDataFolderPath().
// ------------------------------------------------------------
Function/S CheckDataFolder(path)
    String path

    String clean = RemoveEnding(path, ":")
    if (!DataFolderExists(clean))
        LogError("CheckDataFolder: folder not found: " + clean)
        LogInfo("CheckDataFolder: creating: " + clean)
        NewDataFolder/O $clean
    endif

    return clean + ":"
End

// ------------------------------------------------------------
// Function: StartAxisSync
// Purpose : Starts a background task that synchronizes the
//           bottom axis between two hosted subgraphs.
//           Only one sync instance allowed at a time.
// Inputs  : panel_name  - parent panel name
//           subgraph_a  - first subgraph (source on first check)
//           subgraph_b  - second subgraph
// ------------------------------------------------------------
Function StartAxisSync(panel_name, subgraph_a, subgraph_b)
    String panel_name, subgraph_a, subgraph_b

    NewDataFolder/O root:Packages

    // Check if already in use
    NVAR/Z status = root:Packages:AxisSync_status
    if (NVAR_Exists(status) && status == 1)
        SVAR/Z active = root:Packages:AxisSync_panel
        LogError("StartAxisSync: already in use by panel: " + active)
        return 0
    endif

    // Register globals
    Variable/G root:Packages:AxisSync_status = 1
    String/G  root:Packages:AxisSync_panel   = panel_name
    String/G  root:Packages:AxisSync_subA    = subgraph_a
    String/G  root:Packages:AxisSync_subB    = subgraph_b
    Variable/G root:Packages:AxisSync_axMin  = NaN
    Variable/G root:Packages:AxisSync_axMax  = NaN

    CtrlNamedBackground SyncAxis, period=6, proc=SyncAxisBG
    CtrlNamedBackground SyncAxis, start
    LogInfo("StartAxisSync: started for panel: " + panel_name)
End


// ------------------------------------------------------------
// Function: StopAxisSync
// Purpose : Stops the axis sync background task and releases
//           the dynamic_window_status lock.
// ------------------------------------------------------------
Function StopAxisSync()
    CtrlNamedBackground SyncAxis, stop

    KillVariables/Z root:Packages:AxisSync_axMin
    KillVariables/Z root:Packages:AxisSync_axMax
    KillStrings/Z   root:Packages:AxisSync_panel
    KillStrings/Z   root:Packages:AxisSync_subA
    KillStrings/Z   root:Packages:AxisSync_subB

    // Release lock
    Variable/G root:Packages:AxisSync_status = 0
    LogInfo("StopAxisSync: stopped, lock released.")
End


// ------------------------------------------------------------
// Function: SyncAxisBG
// Purpose : Background task — reads bottom axis globals and
//           replicates changes bidirectionally between subA
//           and subB.
// ------------------------------------------------------------
Function SyncAxisBG(s)
    STRUCT WMBackgroundStruct &s

    SVAR/Z panel_name = root:Packages:AxisSync_panel
    SVAR/Z subA       = root:Packages:AxisSync_subA
    SVAR/Z subB       = root:Packages:AxisSync_subB
    NVAR/Z lastMin    = root:Packages:AxisSync_axMin
    NVAR/Z lastMax    = root:Packages:AxisSync_axMax

    if (!SVAR_Exists(panel_name) || !WinType(panel_name))
        StopAxisSync()
        return 1
    endif

    String winA = panel_name + "#" + subA
    String winB = panel_name + "#" + subB

    GetAxis/W=$winA/Q bottom
    Variable aMin = V_min
    Variable aMax = V_max

    GetAxis/W=$winB/Q bottom
    Variable bMin = V_min
    Variable bMax = V_max

    if (aMin != lastMin || aMax != lastMax)
        lastMin = aMin
        lastMax = aMax
        SetAxis/W=$winB bottom aMin, aMax
    elseif (bMin != lastMin || bMax != lastMax)
        lastMin = bMin
        lastMax = bMax
        SetAxis/W=$winA bottom bMin, bMax
    endif

    return 0
End


// ------------------------------------------------------------
// Function: RawPanelKillHook
// Purpose : Stops axis sync when the registered panel is closed.
// ------------------------------------------------------------
Function RawPanelKillHook(s)
    STRUCT WMWinHookStruct &s

    if (s.eventCode == 2)    // 2 = kill
        StopAxisSync()
    endif
    return 0
End

Function ColorTraces(win_name, color_mode)
    String win_name
    Variable color_mode

    String traceList = TraceNameList(win_name, ";", 1)
    Variable n = ItemsInList(traceList)
    if (n == 0)
        LogWarn("ColorTraces: no traces found in " + win_name)
        return 0
    endif

    Variable i, r, g, b

    for (i = 0; i < n; i += 1)
        String tName = StringFromList(i, traceList)

        switch (color_mode)
            case 0:    // single color — default red
                r = 65535
                g = 0
                b = 0
                break

			case 1:    // gradient by trace index — Rainbow-like colormap
			    Variable t =1-( i / max(n - 1, 1))
			    if (t < 0.25)
			        r = 0
			        g = round(65535 * (t / 0.25))
			        b = 65535
			    elseif (t < 0.5)
			        r = 0
			        g = 65535
			        b = round(65535 * (1 - (t - 0.25) / 0.25))
			    elseif (t < 0.75)
			        r = round(65535 * ((t - 0.5) / 0.25))
			        g = 65535
			        b = 0
			    else
			        r = 65535
			        g = round(65535 * (1 - (t - 0.75) / 0.25))
			        b = 0
			    endif
			    break
			        
        endswitch

        ModifyGraph/W=$win_name rgb($tName)=(r, g, b)
    endfor

    LogInfo("ColorTraces: mode=" + num2str(color_mode) + " applied to " + win_name)
End


// ------------------------------------------------------------
// Function: LoadCividis
// Purpose : Loads the cividis color table wave from the Igor
//           Pro Color Tables folder into root:Packages:ColorTables:Misc.
//           No-op if already loaded.
// ------------------------------------------------------------
Function LoadCividis()
    if (WaveExists(root:Packages:ColorTables:Misc:cividis))
        return 0
    endif
    NewDataFolder/O root:Packages
    NewDataFolder/O root:Packages:ColorTables
    NewDataFolder/O root:Packages:ColorTables:Misc
    String/G root:Packages:ColorTables:oldDF = GetDataFolder(1)
    SetDataFolder root:Packages:ColorTables:Misc
    LoadWave/H/O/P=Igor ":Color Tables:Misc:cividis.ibw"
    SetDataFolder root:Packages:ColorTables:oldDF
    KillStrings/Z root:Packages:ColorTables:oldDF
End


// ------------------------------------------------------------
// Function: CividisRGB
// Purpose : Returns interpolated RGB values from the native
//           Igor cividis color table wave.
// Inputs  : t - normalized position in colormap (0–1)
// Outputs : r, g, b via pass-by-reference (0–65535 range)
// ------------------------------------------------------------
Function CividisRGB(t, r, g, b)
    Variable t
    Variable &r, &g, &b

    LoadCividis()
    Wave civ = root:Packages:ColorTables:Misc:cividis

    Variable n    = DimSize(civ, 0)
    t             = min(max(t, 0), 1)
    Variable idx  = t * (n - 1)
    Variable i0   = floor(idx)
    Variable i1   = min(i0 + 1, n - 1)
    Variable frac = idx - i0

    r = round(civ[i0][0] + frac * (civ[i1][0] - civ[i0][0]))
    g = round(civ[i0][1] + frac * (civ[i1][1] - civ[i0][1]))
    b = round(civ[i0][2] + frac * (civ[i1][2] - civ[i0][2]))
End