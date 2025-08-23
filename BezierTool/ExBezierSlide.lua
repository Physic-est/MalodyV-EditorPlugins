------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'ExBezierSlide'
PluginMode = 7
PluginType = 2
PluginRequire = '6.4.2'
PluginIcon = 'ExBezierSlide.png'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local PointType = {
    P1 = 1,
    P2 = 2,
    ControlPoint = 3
}

local P1 = nil
local P2 = nil
local ControlPoints = {}

local P1Module = nil
local P2Module = nil
local CPModule = {}
local P1TextModule = nil
local P2TextModule = nil
local CPTextModule = {}

local PreviewModuleCount = 0

local SelectedNote = nil
local SelectedPoint = nil

local DevideLevel = 20
local PointCount = 1

function Reset()
    P1 = nil
    P2 = nil
    ControlPoints = {}
    P1Module = nil
    P2Module = nil
    CPModule = {}
    P1TextModule = nil
    P2TextModule = nil
    CPTextModule = {}
    PreviewModuleCount = 0
    SelectedNote = nil
    SelectedPoint = nil
end

function SetParameters()
    -- P1 (Head)
    P1 = {
        X = Editor:GetNoteX(SelectedNote),
        Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, true)),
    }

    -- P2 (Tail)
    local segmentsCount = Editor:GetNoteSlideBodyCount(SelectedNote)
    P2 = {
        X = Editor:GetNoteX(SelectedNote) + Editor:GetNoteSlideBodyX(SelectedNote, segmentsCount - 1),
        Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, false)),
    }

    -- ControlPoint
    for i = 1, PointCount do
        ControlPoints[i] = {
            X = P1.X + (i * (P2.X - P1.X) / (PointCount + 1)),
            Y = P1.Y + (i * (P2.Y - P1.Y) / (PointCount + 1)),
        }
    end
end

function UpdateModules()
    -- Head Module
    P1Module = Editor:AddSprite('m-' .. SelectedNote .. 'p1', 'editor-bezier-cp.png')
    P1Module.Beat = PointToBeat(P1.Y)
    P1Module.X = math.floor(100 * P1.X / 256)
    -- Hint Text
    P1TextModule = Editor:AddText('t-' .. SelectedNote .. 'p1', 'Start')
    P1TextModule.Beat = P1Module.Beat
    P1TextModule.X = P1Module.X + 1

    -- Tail Module
    P2Module = Editor:AddSprite('m-' .. SelectedNote .. 'p2', 'editor-bezier-cp.png')
    P2Module.Beat = PointToBeat(P2.Y)
    P2Module.X = math.floor(100 * P2.X / 256)
    -- Hint Text
    P2TextModule = Editor:AddText('t-' .. SelectedNote .. 'p2', 'End')
    P2TextModule.Beat = P2Module.Beat
    P2TextModule.X = P2Module.X + 1

    -- ControlPoint Module
    for i = 1, PointCount do
        CPModule[i] = Editor:AddSprite('m-' .. SelectedNote .. 'control' .. i, 'editor-bezier-cp.png')
        CPModule[i].Beat = PointToBeat(ControlPoints[i].Y)
        CPModule[i].X = math.floor(100 * ControlPoints[i].X / 256)
        -- Hint Text
        CPTextModule[i] = Editor:AddText('t-' .. SelectedNote .. 'control' .. i, 'P' .. i)
        CPTextModule[i].Beat = CPModule[i].Beat
        CPTextModule[i].X = CPModule[i].X + 1
    end
end

------------------------------------------------------------
-- プラグイン起動時
------------------------------------------------------------
function OnActive()
    Reset()
    local notes = Editor:GetSelectNotes()
    local nid = notes[0]
    local notesCount = notes == nil and 0 or notes.Length

    -- ノーツが選択されていない、または2つ以上されている場合は考慮しない
    if notesCount ~= 1 then
        Editor:ShowMessage("Please select one slide note !")
        return
    end

    -- Slide 以外の場合は考慮しない
    if Editor:GetNoteType(nid) ~= NoteType.Slide then
        Editor:ShowMessage("Please select one slide note !")
        return
    end

    SelectedNote = nid
    Editor:GetUserInput('Please enter the number of control points.', tostring(PointCount),
        function(value)
            local count = tonumber(value)
            if count == nil then
                Editor:ShowMessage("Invalid input. Please enter a number between 1 and 10.")
                count = 1
            elseif count < 1 then
                count = 1
            elseif count > 10 then
                count = 10
            end

            PointCount = count
            SetParameters()
            UpdateModules()
        end
    )
end

------------------------------------------------------------
-- プラグイン終了時
------------------------------------------------------------
function OnDeactive()
    Editor:ShowTip('')
    Editor:RemoveModule('m-' .. SelectedNote .. 'p1')
    Editor:RemoveModule('m-' .. SelectedNote .. 'p2')
    for i = 1, PointCount do
        Editor:RemoveModule('m-' .. SelectedNote .. 'control' .. i)
    end
    Editor:RemoveModule('t-' .. SelectedNote .. 'p1')
    Editor:RemoveModule('t-' .. SelectedNote .. 'p2')
    for i = 1, PointCount do
        Editor:RemoveModule('t-' .. SelectedNote .. 'control' .. i)
    end
    Reset()
end

------------------------------------------------------------
-- クリック時
------------------------------------------------------------
function OnClick() return end

------------------------------------------------------------
-- ドラッグ開始時
------------------------------------------------------------
function OnDragStart()
    local offsetX = 10
    local offsetY = BeatToPoint(Editor:MakeBeat(0, 1, 8))
    local clickX = Editor:GetClickX()
    local clickY = BeatToPoint(Editor:GetClickBeatFree())

    SelectedPoint = nil

    if P2.Y - offsetY <= clickY and clickY <= P2.Y + offsetY then
        if P2.X - offsetX <= clickX and clickX <= P2.X + offsetX then
            SelectedPoint = PointType.P2
            return
        end
    end

    for i = 1, PointCount do
        if ControlPoints[i].Y - offsetY <= clickY and clickY <= ControlPoints[i].Y + offsetY then
            if ControlPoints[i].X - offsetX <= clickX and clickX <= ControlPoints[i].X + offsetX then
                SelectedPoint = PointType.ControlPoint + i
            end
        end
    end
end

------------------------------------------------------------
-- ドラッグ中
------------------------------------------------------------
function OnDragMove()
    if SelectedNote ~= nil and SelectedPoint ~= nil then
        if SelectedPoint == PointType.P2 then
            P2 = {
                X = Editor:GetClickX(),
                Y = BeatToPoint(Editor:GetClickBeatFree()),
            }
            if P2.Y < P1.Y then
                P2.Y = P1.Y
            end
            local maxY = 0
            for i = 1, PointCount do
                if maxY < ControlPoints[i].Y then
                    maxY = ControlPoints[i].Y
                end
            end
            if P2.Y < maxY then
                P2.Y = maxY
            end
        end

        for i = 1, PointCount do
            if SelectedPoint == PointType.ControlPoint + i then
                ControlPoints[i] = {
                    X = Editor:GetClickX(),
                    Y = BeatToPoint(Editor:GetClickBeatFree()),
                }
                if ControlPoints[i].Y > P2.Y then
                    ControlPoints[i].Y = P2.Y
                elseif ControlPoints[i].Y < P1.Y then
                    ControlPoints[i].Y = P1.Y
                end
            end
        end

        Editor:StartBatch()
        Editor:DeleteNoteSlideBody(SelectedNote)

        local totalBeat = PointToBeat(P2.Y - P1.Y)
        local segmentsCount = DevideLevel * (math.floor(BeatToPoint(totalBeat) / 2) + 1)
        local allPoints = MakePointsArray(P1, ControlPoints, P2)

        -- Preview Module をクリア
        for pre = 1, PreviewModuleCount do
            Editor:RemoveModule('m-' .. SelectedNote .. '-' .. pre)
        end

        for seg = 1, segmentsCount do
            local t = Bezier(allPoints, seg / segmentsCount)
            local mod = Editor:AddSprite('m-' .. SelectedNote .. '-' .. seg, 'editor-wipe-ex.png')
            mod.Width = math.floor(100 * Editor:GetNoteWidth(SelectedNote) / 256)
            mod.Height = 10
            mod.Beat = PointToBeat(t.Y)
            mod.X = math.floor(100 * t.X / 256)
        end

        PreviewModuleCount = segmentsCount
        UpdateModules()

        Editor:FinishBatch()
    end
end

------------------------------------------------------------
-- ドラッグ終了
------------------------------------------------------------
function OnDragEnd()
    Editor:StartBatch()
    Editor:DeleteNoteSlideBody(SelectedNote)

    local totalBeat = PointToBeat(P2.Y - P1.Y)
    local segmentsCount = DevideLevel * (math.floor(BeatToPoint(totalBeat) / 2) + 1)
    local allPoints = MakePointsArray(P1, ControlPoints, P2)

    for seg = 1, segmentsCount do
        local t = Bezier(allPoints, seg / segmentsCount)
        Editor:AddNoteSlideBody(SelectedNote, PointToBeat(t.Y - P1.Y))
        Editor:SetNoteSlideBodyX(SelectedNote, seg - 1, math.floor(t.X - P1.X))
        Editor:RemoveModule('m-' .. SelectedNote .. '-' .. seg)
    end

    UpdateModules()

    Editor:FinishBatch()
end

------------------------------------------------------------
-- Utilities
------------------------------------------------------------

function BeatToPoint(beat)
    return beat.beat + (beat.numor / beat.denom)
end

function PointToBeat(point)
    local beat = math.floor(point)
    local numor = math.floor((point - beat) * 1000)
    local denom = 1000
    return { beat = beat, numor = numor, denom = denom }
end

function MakePointsArray(p1, points, p2)
    local pointsArray = {}
    table.insert(pointsArray, p1)

    for i = 1, #points do
        table.insert(pointsArray, points[i])
    end

    table.insert(pointsArray, p2)
    return pointsArray
end

function Bezier(points, t)
    local temp = {}
    for i = 1, #points do
        temp[i] = { X = points[i].X, Y = points[i].Y }
    end

    local n = #points
    for r = 1, n - 1 do
        for i = 1, n - r do
            temp[i] = {
                X = (1 - t) * temp[i].X + t * temp[i + 1].X,
                Y = (1 - t) * temp[i].Y + t * temp[i + 1].Y
            }
        end
    end
    return temp[1]
end
