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
            plot_raw_panel()
            //plot_stim()
            break

        case "btnRamp":
            menu_tempresponse()
            break

        case "btnplotamp":
            plot_amp("raw")
            break

        case "btnIV":
            AnalizarIVporCanal()
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

    Variable x_range  = rightx(w) - leftx(w)
    Variable x_a      = leftx(w) + x_range * pos_a
    Variable x_b      = leftx(w) + x_range * pos_b
    String trace_name = NameOfWave(w)

    Cursor/H=2/L=1/W=$win_name A, $trace_name, x_a
    Cursor/H=2/L=1/W=$win_name B, $trace_name, x_b
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