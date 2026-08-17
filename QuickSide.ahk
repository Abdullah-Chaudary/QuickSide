#Requires AutoHotkey v2.0
#SingleInstance Force
SetWinDelay 1

AppDir     := A_AppData "\QuickSide"
ConfigFile := AppDir "\config.ini"
TodosFile  := AppDir "\todos.txt"
NotesFile  := AppDir "\notes.txt"

if !DirExist(AppDir)
    DirCreate(AppDir)

cfg       := LoadConfig()
PANEL_W   := cfg.width
win       := BuildGui()
sq        := { id: 0, x: 0, y: 0, w: 0, h: 0, max: false, valid: false }
PMon      := MonitorGetPrimary()
animating := false
isOpen    := false
lastTab   := 1

RegisterHotkey(cfg.hotkey)
ApplyAutostart(cfg.autostart)

SetTimer(ShowStartupTip, -800)
LoadTodos()

tray := A_TrayMenu
tray.Delete()
tray.Add("Open QuickSide", TogglePanel)
tray.Add()
tray.Add("Exit", (*) => ExitApp())
tray.Default := "Open QuickSide"

ShowStartupTip(*) {
    global cfg
    TrayTip("Press " cfg.hotkey " to toggle the panel", "QuickSide", 1)
}

#HotIf WinActive("ahk_id " win.hwnd) and win.FocusedCtrl = newItem
Enter::AddTodo()
#HotIf

LoadConfig() {
    global ConfigFile
    c := { hotkey: "!q", autostart: 0, width: 400 }
    if FileExist(ConfigFile) {
        for line in StrSplit(FileRead(ConfigFile), "`n", "`r") {
            p := InStr(line, "=")
            if !p
                continue
            k := SubStr(line, 1, p - 1)
            v := SubStr(line, p + 1)
            if k = "hotkey"
                c.hotkey := v
            else if k = "autostart"
                c.autostart := (v = "1")
            else if k = "width"
                c.width := Integer(v)
        }
    }
    if c.width < 240 or c.width > 900
        c.width := 400
    return c
}

SaveConfig() {
    global cfg, ConfigFile
    f := FileOpen(ConfigFile, "w", "UTF-8-RAW")
    f.Write("hotkey=" cfg.hotkey "`nautostart=" (cfg.autostart ? 1 : 0) "`nwidth=" cfg.width "`n")
    f.Close()
}

BuildGui() {
    global cfg, PANEL_W, NotesFile
    g := Gui("+AlwaysOnTop +ToolWindow")
    g.Title := "QuickSide"
    g.SetFont("s10", "Segoe UI")
    g.OnEvent("Close", HidePanel)
    g.OnEvent("Escape", HidePanel)

    global tabs := g.Add("Tab3", "x0 y0 w" PANEL_W " h610", ["ToDo", "Notes", "Settings"])
    tabs.OnEvent("Change", TabChanged)

    tabs.UseTab(1)
    global newItem := g.Add("Edit", "x10 y45 w" (PANEL_W - 125) " h26")
    global addBtn := g.Add("Button", "x" (PANEL_W - 105) " y44 w95 h28", "Add")
    addBtn.OnEvent("Click", AddTodo)
    global lv := g.Add("ListView", "x10 y80 w" (PANEL_W - 30) " h470 Checked", ["", "Task"])
    lv.ModifyCol(1, 30)
    lv.ModifyCol(2, PANEL_W - 70)
    lv.OnEvent("DoubleClick", ToggleSelected)
    lv.OnEvent("ItemCheck", (*) => SaveTodos())
    global delBtn := g.Add("Button", "x10 y560 w" (PANEL_W - 210) " h26", "Delete Selected")
    delBtn.OnEvent("Click", DeleteSelected)
    global clearBtn := g.Add("Button", "x" (PANEL_W - 190) " y560 w170 h26", "Clear Done")
    clearBtn.OnEvent("Click", ClearDone)

    tabs.UseTab(2)
    global note := g.Add("Edit", "x10 y45 w" (PANEL_W - 30) " h535 +Multi +WantTab +Wrap +VScroll")
    note.Value := FileExist(NotesFile) ? FileRead(NotesFile) : ""
    note.OnEvent("Change", StartNoteSaveTimer)

    tabs.UseTab(3)
    g.Add("Text", "x10 y50", "Global hotkey (click box, press keys, Apply):")
    global hkCtrl := g.Add("Hotkey", "x10 y72 w" (PANEL_W - 120))
    hkCtrl.Value := cfg.hotkey
    global hkBtn := g.Add("Button", "x" (PANEL_W - 100) " y71 w90 h26", "Apply")
    hkBtn.OnEvent("Click", ApplyHotkey)
    global autoCk := g.Add("Checkbox", "x10 y115", "Run at Windows startup")
    autoCk.Value := cfg.autostart
    autoCk.OnEvent("Click", ToggleAutostart)
    g.Add("Text", "x10 y155", "Panel width in px (240-900):")
    global wEdit := g.Add("Edit", "x10 y176 w80")
    wEdit.Value := cfg.width
    global wBtn := g.Add("Button", "x100 y174 w70 h26", "Set")
    wBtn.OnEvent("Click", ApplyWidth)

    tabs.UseTab(0)
    return g
}

TabChanged(*) {
    global lastTab, tabs
    lastTab := tabs.Value
}

RegisterHotkey(hk) {
    Hotkey(hk, TogglePanel, "On")
}

TogglePanel(*) {
    global isOpen, animating
    if animating
        return
    if isOpen
        HidePanel()
    else
        ShowPanel()
}

ShowPanel(*) {
    global isOpen, animating, sq, PMon, win, PANEL_W, lastTab, newItem, note
    if isOpen or animating
        return

    sq.valid := false
    PMon := MonitorGetPrimary()
    wid := WinGetID("A")

    if wid and wid != win.hwnd and WinExist("ahk_id " wid) {
        title := WinGetTitle("ahk_id " wid)
        if title {
            try {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " wid)
                wasMax := WinGetMinMax("ahk_id " wid) = 1
                mon := GetMonitorOfPoint(wx + ww // 2, wy + wh // 2)
                if mon > 0
                    PMon := mon
                if wasMax
                    WinRestore("ahk_id " wid)
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " wid)
                if ww > 300
                    sq := { id: wid, x: wx, y: wy, w: ww, h: wh, max: wasMax, valid: true }
            } catch {
                sq.valid := false
            }
        }
    }

    MonitorGetWorkArea(PMon, &ax1, &ay1, &ax2, &ay2)
    ph := Min(600, ay2 - ay1)
    py := ay2 - ph
    pw := PANEL_W
    tx := ax2 - pw

    if sq.valid and sq.max {
        sq.x := ax1
        sq.y := ay1
        sq.w := ax2 - ax1
        sq.h := ay2 - ay1
    }

    animating := true
    win.Show("x" ax2 " y" py " w" pw " h" ph)
    if sq.valid and sq.max
        WinMove(sq.x, sq.y, sq.w, sq.h, "ahk_id " sq.id)

    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    steps := 300
    start := A_TickCount
    dur := 250
    try {
        loop steps {
            k := A_Index
            win.Move(ax2 - Round(k / steps * pw), py, pw, ph)
            target := start + Round(k / steps * dur)
            while A_TickCount < target {
                Sleep 0
            }
        }
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)

    if sq.valid
        WinMove(sq.x, sq.y, sq.w - pw, sq.h, "ahk_id " sq.id)

    animating := false
    isOpen := true

    WinActivate(win)
    if lastTab = 1
        newItem.Focus()
    else if lastTab = 2
        note.Focus()
}

HidePanel(*) {
    global isOpen, animating, sq, PMon, win, PANEL_W
    if !isOpen or animating
        return
    SaveNotes()
    animating := true
    pw := PANEL_W
    MonitorGetWorkArea(PMon, &ax1, &ay1, &ax2, &ay2)
    ph := Min(600, ay2 - ay1)
    py := ay2 - ph
    tx := ax2 - pw

    if sq.valid
        WinMove(sq.x, sq.y, sq.w, sq.h, "ahk_id " sq.id)

    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    steps := 300
    start := A_TickCount
    dur := 250
    try {
        loop steps {
            k := A_Index
            win.Move(tx + Round(k / steps * pw), py, pw, ph)
            target := start + Round(k / steps * dur)
            while A_TickCount < target {
                Sleep 0
            }
        }
    }
    win.Hide()
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    animating := false
    isOpen := false

    if sq.valid and WinExist("ahk_id " sq.id) {
        WinMove(sq.x, sq.y, sq.w, sq.h, "ahk_id " sq.id)
        if sq.max
            WinMaximize("ahk_id " sq.id)
        if WinActive("ahk_id " win.hwnd)
            WinActivate("ahk_id " sq.id)
    }
    sq.valid := false
}

GetMonitorOfPoint(x, y) {
    n := MonitorGetCount()
    loop n {
        MonitorGetWorkArea(A_Index, &x1, &y1, &x2, &y2)
        if x >= x1 and x <= x2 and y >= y1 and y <= y2
            return A_Index
    }
    return 0
}

AddTodo(*) {
    global lv, newItem
    t := Trim(newItem.Value)
    if !t
        return
    lv.Add("", "", t)
    newItem.Value := ""
    SaveTodos()
    newItem.Focus()
}

SaveTodos(*) {
    global lv, TodosFile
    out := ""
    loop lv.GetCount() {
        i := A_Index
        checked := (lv.GetNext(i - 1, "C") = i)
        out .= (checked ? "1" : "0") "|" lv.GetText(i, 2) "`n"
    }
    f := FileOpen(TodosFile, "w", "UTF-8-RAW")
    f.Write(out)
    f.Close()
}

LoadTodos(*) {
    global lv, TodosFile
    lv.Delete()
    if !FileExist(TodosFile)
        return
    for line in StrSplit(FileRead(TodosFile), "`n", "`r") {
        if !line
            continue
        p := InStr(line, "|")
        if !p
            continue
        row := lv.Add("", "", SubStr(line, p + 1))
        if SubStr(line, 1, p - 1) = "1"
            lv.Modify(row, "Check")
    }
}

ToggleSelected(*) {
    global lv
    r := lv.GetNext(0, "F")
    if r
        lv.Modify(r, lv.GetNext(r - 1, "C") = r ? "-Check" : "Check")
    SaveTodos()
}

DeleteSelected(*) {
    global lv
    n := lv.GetCount("S")
    if !n
        return
    loop n
        lv.Delete(lv.GetNext(0, "S"))
    SaveTodos()
}

ClearDone(*) {
    global lv
    loop {
        r := lv.GetNext(0, "C")
        if !r
            break
        lv.Delete(r)
    }
    SaveTodos()
}

StartNoteSaveTimer(*) {
    SetTimer(SaveNotes, 0)
    SetTimer(SaveNotes, -300)
}

SaveNotes(*) {
    global note, NotesFile
    f := FileOpen(NotesFile, "w", "UTF-8")
    f.Write(note.Value)
    f.Close()
}

ApplyHotkey(*) {
    global hkCtrl, cfg
    txt := hkCtrl.Value
    if !txt {
        MsgBox("Press a key combination in the box, then Apply.")
        return
    }
    try {
        if cfg.hotkey
            Hotkey(cfg.hotkey, "Off")
        Hotkey(txt, TogglePanel, "On")
    } catch {
        if cfg.hotkey
            Hotkey(cfg.hotkey, TogglePanel, "On")
        MsgBox("That key combination can't be registered.")
        return
    }
    cfg.hotkey := txt
    SaveConfig()
    TrayTip("Hotkey set to " txt, "QuickSide", 1)
}

ToggleAutostart(ck, *) {
    global cfg
    cfg.autostart := ck.Value
    ApplyAutostart(cfg.autostart)
    SaveConfig()
}

ApplyAutostart(on) {
    key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    if on
        RegWrite('"' A_AhkPath '" "' A_ScriptFullPath '"', "REG_SZ", key, "QuickSide")
    else if RegRead(key, "QuickSide", "") != ""
        RegDelete(key, "QuickSide")
}

ApplyWidth(*) {
    global wEdit, cfg
    if !RegExMatch(wEdit.Value, "^\d+$") {
        MsgBox("Enter a number between 240 and 900.")
        return
    }
    v := Integer(wEdit.Value)
    if v < 240 or v > 900 {
        MsgBox("Panel width must be between 240 and 900.")
        return
    }
    cfg.width := v
    SaveConfig()
    Reload
}