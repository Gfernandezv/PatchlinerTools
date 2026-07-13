#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

Menu "Analysis"
    submenu "Nanion"
        "Panel", start_panels()
    End
end

// ------------------------------------------------------------
// Function: start_panels
// Purpose : Entry point for the Nanion Analysis toolkit.
//           Opens the main panel, log console, and data browser.
//           Initializes the root Packages folder.
// ------------------------------------------------------------
Function start_panels()

    // Initialize root Packages folder
    NewDataFolder/O $(GetDataFolder(1)+"Packages")

    Execute "LogConsole()"
    Execute "Main_panel()"
    if (!WinType("DataBrowser"))
    		CreateBrowser
        //Execute "DataBrowser/W=(0, 44, 710, 740)"
    endif

    LogInfo("=== Nanion Analysis Toolkit started ===")
    LogInfo("Igor version: " + num2str(IgorVersion()))
    LogInfo("Current folder: " + GetDataFolder(1))
End


Window Main_panel() : Panel
    DoWindow/K TabPanel
    NewPanel/K=0/N=TabPanel/W=(753,68,1031,393) as "Nanion Analysis"

    // --- TabControl ---
    TabControl tb, pos={15,15}, size={250,250}, proc=TabProc
    TabControl tb, tabLabel(0)="Organize"
    TabControl tb, tabLabel(1)="Ramp",  value=0
    TabControl tb, tabLabel(2)="IV",    value=0

    // --- Tab 0: Organize ---
    Button btnorder,   pos={24,45},  size={100,20}, proc=LogButtonProc, title="Organize data", disable=0

    // --- Tabs 1 and 2: shared ---
    Button btnStim,    pos={24,45},  size={100,20}, proc=LogButtonProc, title="Plot Stim",     disable=1

    // --- Tab 1: Ramp ---
    Button btnRamp,    pos={24,75},  size={100,20}, proc=LogButtonProc, title="Ramp Analysis", disable=1
    Button btnplotamp, pos={24,105}, size={100,20}, proc=LogButtonProc, title="Amp Analysis",  disable=1

    // --- Tab 2: IV ---
    Button btnIV,      pos={24,75},  size={100,20}, proc=LogButtonProc, title="IV Analysis",   disable=1
    Button btnIVgraph, pos={24,105}, size={100,20}, proc=LogButtonProc, title="IV Graph",      disable=1
EndMacro


Function TabProc(tca) : TabControl
    STRUCT WMTabControlAction &tca

    Variable tabNum, isTab0, isTab1, isTab2

    switch (tca.eventCode)
        case 2:
            tabNum = tca.tab

            isTab0 = (tabNum == 0)
            isTab1 = (tabNum == 1)
            isTab2 = (tabNum == 2)

            // Tab 0: Organize
            ModifyControl btnorder   disable = !isTab0

            // Tabs 1 and 2: shared
            ModifyControl btnStim    disable = isTab0

            // Tab 1: Ramp only
            ModifyControl btnRamp    disable = !isTab1
            ModifyControl btnplotamp disable = !isTab1

            // Tab 2: IV only
            ModifyControl btnIV      disable = !isTab2
            ModifyControl btnIVgraph disable = !isTab2
            break
    endswitch

    return 0
End


// ------------------------------------------------------------
// Function: menu_tempresponse
// Purpose : Prompts the user for ramp analysis parameters,
//           stores them, and launches tempresponse().
// ------------------------------------------------------------
Function menu_tempresponse()

    // Retrieve last used parameters for this folder (NaN = retrieve mode)
    String chan      = GetDataFolder(1)
    Variable basal_i = nvar_storer("ramp_basal_i", NaN, chan)
    Variable peak_f  = nvar_storer("ramp_peak_f",  NaN, chan)
    Variable temp    = nvar_storer("ramp_temp",     NaN, chan)

    // Extract channel name from folder path
    Variable numFolders = ItemsInList(chan, ":")
    String chanexp = StringFromList((numFolders-2), chan, ":")

    Prompt basal_i, "Ramp start (s):"
    Prompt peak_f,  "Peak time (s):"
    Prompt temp,    "Temperature (°C):"
    Prompt chanexp, "Channel:"
    DoPrompt "Ramp analysis parameters", basal_i, peak_f, temp, chanexp

    if (V_Flag)
        LogWarn("Ramp analysis cancelled by user.")
        return -1
    endif

    // Store accepted parameters
    nvar_storer("ramp_basal_i", basal_i, chan)
    nvar_storer("ramp_peak_f",  peak_f,  chan)
    nvar_storer("ramp_temp",    temp,    chan)
    svar_storer("chanexp",      chanexp, chan)

    LogInfo("Parameters accepted. Analyzing temperature: " + num2str(temp) + " °C")
    tempresponse(basal_i, peak_f, temp, chanexp)
End


// ------------------------------------------------------------
// Function: menu_leaksustraction
// Purpose : Prompts the user for leak subtraction parameters
//           and stores them for later use.
// Notes   : Analysis function call is pending (TODO).
// ------------------------------------------------------------
Function menu_leaksustraction()

    // Retrieve last used parameters for this folder (NaN = retrieve mode)
    String chan      = GetDataFolder(1)
    Variable ramp_i  = nvar_storer("ramp_basal_i", NaN, chan)
    Variable ramp_f  = nvar_storer("ramp_peak_f",  NaN, chan)
    Variable v_ini   = nvar_storer("V_Ramp_ini",   NaN, chan)
    Variable v_fin   = nvar_storer("V_Ramp_fin",   NaN, chan)

    Prompt ramp_i, "Ramp start (s):"
    Prompt ramp_f, "Ramp end (s):"
    Prompt v_ini,  "Ramp start potential (mV):"
    Prompt v_fin,  "Ramp end potential (mV):"
    DoPrompt "Leak subtraction parameters", ramp_i, ramp_f, v_ini, v_fin

    if (V_Flag)
        LogWarn("Leak subtraction cancelled by user.")
        return -1
    endif

    // Store accepted parameters
    nvar_storer("ramp_basal_i", ramp_i, chan)
    nvar_storer("ramp_peak_f",  ramp_f, chan)
    nvar_storer("V_Ramp_ini",   v_ini,  chan)
    nvar_storer("V_Ramp_fin",   v_fin,  chan)

    LogInfo("Leak subtraction parameters accepted.")
    // TODO: call leak subtraction analysis function
End
