------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'GizaSlide2'
PluginMode = 7
PluginType = 2
PluginRequire = '6.4.2'
PluginIcon = 'GizaSlide2.png'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local PointType = {
    GripPoint = 1
}

local P1 = nil
local P2 = nil
local GripPoint = nil

local GPModule = nil
local GPLineModule = nil

local SelectedNote = nil
local OriginalSegments = {}
local SelectedPoint = nil

function Reset()
    P1 = nil
    P2 = nil
    GripPoint = nil
    P1Module = nil
    P2Module = nil
    CPModule = nil
    P1TextModule = nil
    P2TextModule = nil
    SelectedNote = nil
    OriginalSegments = {}
    SelectedPoint = nil
end

function SetParameters()
    -- Head
    P1 = {
        X = Editor:GetNoteX(SelectedNote),
        Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, true)),
    }

    -- Tail
    local segmentsCount = Editor:GetNoteSlideBodyCount(SelectedNote)
    P2 = {
        X = Editor:GetNoteX(SelectedNote) + Editor:GetNoteSlideBodyX(SelectedNote, segmentsCount - 1),
        Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, false)),
    }

    for i = 0, segmentsCount - 1 do
        local seg = {}
        seg.X = Editor:GetNoteX(SelectedNote) + Editor:GetNoteSlideBodyX(SelectedNote, i)
        seg.Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, true)) +
            BeatToPoint(Editor:GetNoteSlideBodyBeat(SelectedNote, i))
        OriginalSegments[i + 1] = { X = seg.X, Y = seg.Y }
    end

    -- GripPoint
    GripPoint = {
        X = 128,
        Y = P1.Y + ((P2.Y - P1.Y) / 2),
    }
end

function SetModulePoint()
    -- GripPoint Module
    GPModule = Editor:AddSprite('m-' .. SelectedNote .. 'grip', 'editor-grip.png')
    GPModule.Beat = PointToBeat(GripPoint.Y)
    GPModule.X = math.floor(100 * GripPoint.X / 256)

    -- GripPoint Module
    GPLineModule = Editor:AddSprite('m-' .. SelectedNote .. 'grip_line', 'editor-grip-line.png')
    GPLineModule.Beat = PointToBeat(GripPoint.Y)
    GPLineModule.X = 50
    GPLineModule.Width = 100
end

function BeatToPoint(beat)
    return beat.beat + (beat.numor / beat.denom)
end

function PointToBeat(point)
    local beat = math.floor(point)
    local numor = math.floor((point - beat) * 1000)
    local denom = 1000
    return { beat = beat, numor = numor, denom = denom }
end

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
    SetParameters()
    SetModulePoint()
end

function OnDeactive()
    Editor:ShowTip('')
    Editor:RemoveModule('m-' .. SelectedNote .. 'grip')
    Editor:RemoveModule('m-' .. SelectedNote .. 'grip_line')
    Reset()
end

------------------------------------------------------------
-- クリック時
------------------------------------------------------------
function OnClick()
end

------------------------------------------------------------
-- ドラッグ開始時
------------------------------------------------------------
function OnDragStart()
    local offsetX = 10
    local offsetY = BeatToPoint(Editor:MakeBeat(0, 1, 8))
    local clickX = Editor:GetClickX()
    local clickY = BeatToPoint(Editor:GetClickBeat())

    SelectedPoint = nil

    if GripPoint.Y - offsetY <= clickY and clickY <= GripPoint.Y + offsetY then
        if GripPoint.X - offsetX <= clickX and clickX <= GripPoint.X + offsetX then
            SelectedPoint = PointType.GripPoint
            return
        end
    end
end

------------------------------------------------------------
-- ドラッグ中
------------------------------------------------------------
function OnDragMove()
    if SelectedNote ~= nil and SelectedPoint == PointType.GripPoint then
        GripPoint.X = Editor:GetClickX()

        Editor:StartBatch()
        Editor:DeleteNoteSlideBody(SelectedNote)

        for seg = 1, #OriginalSegments do
            Editor:AddNoteSlideBody(SelectedNote, PointToBeat(OriginalSegments[seg].Y - P1.Y))
            Editor:SetNoteSlideBodyX(SelectedNote, seg - 1, math.floor(OriginalSegments[seg].X - P1.X))
        end

        for seg = #OriginalSegments, 1, -1 do
            local dx = GripPoint.X -128
            if seg == 1 then
                Editor:AddNoteSlideBody(SelectedNote,
                    PointToBeat(OriginalSegments[seg].Y - ((OriginalSegments[seg].Y - P1.Y) / 2) - P1.Y))
                Editor:SetNoteSlideBodyX(SelectedNote, seg - 1,
                    math.floor(dx + OriginalSegments[seg].X - P1.X))
            else
                Editor:AddNoteSlideBody(SelectedNote,
                    PointToBeat(OriginalSegments[seg].Y - ((OriginalSegments[seg].Y - OriginalSegments[seg - 1].Y) / 2) -
                        P1.Y))
                Editor:SetNoteSlideBodyX(SelectedNote, seg - 1,
                    math.floor(dx + OriginalSegments[seg].X - P1.X))
            end
        end

        SetModulePoint()

        Editor:FinishBatch()
    end
end

------------------------------------------------------------
-- ドラッグ終了
------------------------------------------------------------
function OnDragEnd()
end
