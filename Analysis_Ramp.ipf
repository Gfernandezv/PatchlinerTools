#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

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
//           Drift correction via SubtractBaseline() (Utils).
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

        // -------------------------------------------------
        // Drift subtraction: correct baseline using mean of first 10 ms
        // -------------------------------------------------
        SubtractBaseline(drift_w, 0.001, 0.011)

        // -------------------------------------------------
        // Mode 0: linear fit to first ramp segment
        // -------------------------------------------------
        Duplicate/O/FREE drift_w, fit
        CurveFit/Q/X=1 line w(t_ini+0.002, t_ini+0.042)
        Wave W_coef

        fit = W_coef[0] + W_coef[1]*x
        fit = w - fit
        Netpeak[i][0] = mean(fit, (peak_f-0.003), (peak_f-0.001))  // mean of last 3 ms in fitted wave

        // -------------------------------------------------
        // Mode 1: linear fit near 0 mV (TODO)
        // -------------------------------------------------

        // -------------------------------------------------
        // Mode 2: no baseline fit
        // -------------------------------------------------
        Netpeak[i][2] = mean(drift_w, (peak_f-0.003), (peak_f-0.001))

        [cm, tau, rs] = pasivas(drift_w, 100, (peak_f+0.0006), (peak_f+0.025))
        pasives[i][0] = cm                // Cm (pF)
        pasives[i][1] = tau               // tau (ms)
        pasives[i][2] = rs                // Rs (MΩ)

        KillWaves drift_w

    endfor

    // Peak wave analysis
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
