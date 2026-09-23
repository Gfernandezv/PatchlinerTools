#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

//====================================================
//   WAVE ORGANIZATION (Administrative)
//====================================================

// ------------------------------------------------------------
// Function: prefix_detector
// Purpose : Prompts the user for a wave prefix, verifies that
//           matching waves exist, stores the prefix, and
//           triggers the initial wave organization.
// Inputs  : User-entered wave prefix string.
// Outputs : Stores Wave_prefix in the Packages folder.
//           Calls sorting_hat() to organize waves.
// Notes   : Depends on the currently active data folder.
// ------------------------------------------------------------
Function prefix_detector()

    String prefix
    Prompt prefix, "Enter wave prefix:"
    DoPrompt "Wave selector", prefix
    if (V_Flag)
        LogWarn("prefix_detector: cancelled by user.")
        return 0
    endif

    // Verify waves exist with the given prefix
    String list = WaveList((prefix + "*"), ";", "")
    if (ItemsInList(list) < 1)
        LogError("No waves found with prefix: " + prefix)
        return 0
    endif

    // Store prefix in Packages folder
    String packages_path = GetDataFolder(1) + "Packages"
    NewDataFolder/O $(packages_path)
    String/G $(packages_path + ":Wave_prefix") = prefix

    LogInfo("Prefix set: " + prefix + " (" + num2str(ItemsInList(list)) + " waves found)")
    sorting_hat(prefix)

End

// ------------------------------------------------------------
// Function: sorting_hat
// Purpose : Organizes raw waves into a two-level folder
//           hierarchy: channel (chan_X) and experiment (exp_X).
// Inputs  : prefix - wave name prefix to match
// Notes   : Runs first_phase (by channel) then second_phase
//           (by experiment) for each wave suffix type.
// ------------------------------------------------------------
Function sorting_hat(prefix)
    String prefix
    String sufs = "_Amp;_Dur;*"
    Variable k

    // First phase: sort by channel
    for (k=0; k<ItemsInList(sufs); k+=1)
        first_phase(prefix, StringFromList(k, sufs))
    endfor

    // Second phase: sort by experiment
    for (k=0; k<ItemsInList(sufs); k+=1)
        second_phase(prefix, StringFromList(k, sufs))
    endfor
End

// ------------------------------------------------------------
// Function: first_phase
// Purpose : Moves waves into per-channel subfolders (chan_X).
// Inputs  : prefix - wave name prefix
//           sufix  - wave name suffix to match
// ------------------------------------------------------------
Function first_phase(prefix, sufix)
    String prefix, sufix

    Variable i, ind
    String current_folder = GetDataFolder(1), signal_folder, exp_folder

    strswitch(sufix)
        case "_Dur":
        case "_Amp":
            ind = 2
            break
        case "*":
            ind = 1
            break
    endswitch

    String pattern = prefix + "*" + sufix
    String list    = WaveList(pattern, ";", "")
    Variable n     = ItemsInList(list)

    if (n == 0)
        LogError("No waves found with suffix: " + sufix)
        return 0
    endif

    String wave_name, valStr, folderName

    // === FIRST SORT: BY CHANNEL ===
    for (i=0; i<n; i+=1)
        wave_name = StringFromList(i, list)

        // Extract channel from wave name
        Variable pos = (ItemsInList(wave_name, "_")) - ind
        valStr     = StringFromList(pos, wave_name, "_")
        folderName = current_folder + "chan_" + valStr

        // Create folder if missing
        if (!DataFolderExists(folderName))
            NewDataFolder/O $folderName
        endif

        MoveWave $wave_name, $(folderName+":")
    endfor

End

// ------------------------------------------------------------
// Function: second_phase
// Purpose : Moves waves from channel folders into per-experiment
//           subfolders (exp_X/Trace or exp_X/Stim).
// Inputs  : prefix - wave name prefix
//           sufix  - wave name suffix to match
// Notes   : Uses ListSubfolders() (Utils) to enumerate chan_X
//           folders instead of parsing DataFolderDir() directly.
// ------------------------------------------------------------
Function second_phase(prefix, sufix)
    String prefix, sufix

    Variable i, j, ind
    String current_folder = GetDataFolder(1), signal_folder

    // === SECOND SORT: BY EXPERIMENT (within each channel folder) ===
    // Use ListSubfolders() (Utils) instead of manual DataFolderDir parsing
    String chan_list  = ListSubfolders(current_folder, "chan_")
    Variable nFolders = ItemsInList(chan_list)
    String pattern = prefix + "*" + sufix, wave_name, valStr

    strswitch(sufix)
        case "_Dur":
        case "_Amp":
            ind = 4
            signal_folder = "Stim"
            break
        case "*":
            ind = 3
            signal_folder = "Trace"
            break
    endswitch

    for (i = 0; i < nFolders; i += 1)

        String folderNameShort = StringFromList(i, chan_list, ";")
        String folderPath      = current_folder + folderNameShort + ":"
        SetDataFolder $folderPath

        String traces = WaveList(pattern, ";", "")
        Variable nTr  = ItemsInList(traces)

        for (j=0; j<nTr; j+=1)
            wave_name = StringFromList(j, traces)

            Variable pos2 = ItemsInList(wave_name, "_") - ind
            valStr = StringFromList(pos2, wave_name, "_")

            String exp_target = folderPath + "exp_" + valStr

            if (!DataFolderExists(exp_target))
                NewDataFolder/O $exp_target
            endif

            if (!DataFolderExists(exp_target + ":" + signal_folder))
                NewDataFolder/O $(exp_target + ":" + signal_folder)
            endif

            MoveWave $wave_name, $(exp_target + ":" + signal_folder + ":")
        endfor

        SetDataFolder current_folder
    endfor

End




//====================================================
//   PASSIVE PROPERTIES (Shared Analysis)
//====================================================

// ------------------------------------------------------------
// Function: expFitRsCm
// Purpose : Exponential fit function used by pasivas().
//           Model: I(t) = A * exp(-t / tau) + offset
// ------------------------------------------------------------
Function expFitRsCm(w, x) : FitFunc
    Wave w
    Variable x
    return w[0] * exp(-x / w[1]) + w[2]
End

// ------------------------------------------------------------
// Function: pasivas
// Purpose : Estimate passive cell properties from the capacitive
//           component of a current wave (response to a voltage step).
// Inputs  : I      - current wave (amperes)
//           deltaV - voltage step amplitude (mV)
//           tStart - start of fitting segment (s)
//           tEnd   - end of fitting segment (s)
// Outputs : Cm_pF    - membrane capacitance (pF)
//           tau_ms   - exponential fit time constant (ms)
//           Rs_MOhm  - series resistance (MΩ)
// Method  :
//   1. Crop wave between tStart and tEnd (Itrans)
//   2. Build time axis in ms (ttrans)
//   3. Fit simple exponential model:
//        I(t) = A * exp(-t / tau) + offset
//   4. Derive passive properties:
//        Rs   = ΔV / I0      (I0 in nA)
//        Rtot = ΔV / offset  (offset in nA)
//        Rm   = Rtot - Rs
//        Cm   = tau / Rs     (pF)
// Notes   : Current must be in amperes. deltaV in millivolts.
//           Requires expFitRsCm defined in this file.
// ------------------------------------------------------------
Function [Variable Cm_pF, Variable tau_ms, Variable Rs_MOhm] pasivas(Wave I, Variable deltaV, Variable tStart, Variable tEnd)
	
    Duplicate/O/R=(tStart, tEnd) I, Itrans

    Variable dt = DimDelta(I, 0) * 1000     // ms
    Make/O/N=(numpnts(Itrans)) ttrans
    SetScale/P x, 0, dt, "", ttrans
    ttrans = p * dt

    Make/O/N=3 coef_fit_rs
    coef_fit_rs[0] = Itrans[0] - Itrans[numpnts(Itrans)-1]   // A ~ I0 - Iss
    coef_fit_rs[1] = 1                                        // tau ~ 1 ms
    coef_fit_rs[2] = Itrans[numpnts(Itrans)-1]               // offset ~ Iss

    FuncFit/Q expFitRsCm coef_fit_rs Itrans /X=ttrans

    // Fit parameters
    Variable A_A   = coef_fit_rs[0]
    tau_ms         = coef_fit_rs[1]
    Variable Iss_A = coef_fit_rs[2]                           // Iss = offset

    // Key currents
    Variable I0_A  = A_A + Iss_A                              // I0 = A + Iss
    Variable I0_nA = abs(I0_A  * 1e9)
    Variable Iss_nA = abs(Iss_A * 1e9)

    Variable eps        = 1e-9
    Rs_MOhm             = abs(deltaV) / max(I0_nA, eps)
    Variable Rtot_MOhm  = abs(deltaV) / max(Iss_nA, eps)
    Variable Rm_MOhm    = max(Rtot_MOhm - Rs_MOhm, 0)
    Variable Rpar_MOhm  = (Rs_MOhm * Rm_MOhm) / max(Rs_MOhm + Rm_MOhm, eps)

    Cm_pF = (tau_ms / max(Rpar_MOhm, eps)) * 1000             // τ(ms)/Rpar(MΩ) = nF → pF

    KillWaves/Z ttrans, Itrans, coef_fit_rs
    return [Cm_pF, tau_ms, Rs_MOhm]

End
