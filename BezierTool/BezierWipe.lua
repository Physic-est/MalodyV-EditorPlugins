-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-08-15
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'BezierWipe'
PluginMode = 7
PluginType = 2
PluginRequire = '6.0.0'
PluginIcon = 'BezierWipe.png'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local P1 = nil
local P2 = nil
local ControlPoint = nil
local SelectedNote = nil

local DevideLevel = 10

function Reset()
    P1 = nil
    P2 = nil
    ControlPoint = nil
    SelectedNote = nil
end

function SetParameters(nid)
    -- Head
    P1 = {
        X = Editor:GetNoteX(nid),
        Y = BeatToPoint(Editor:GetNoteBeat(nid, true)),
        Beat = Editor:GetNoteBeat(nid, true)
    }

    -- Tail
    local segmentsCount = Editor:GetNoteSlideBodyCount(nid)
    P2 = {
        X = Editor:GetNoteX(nid) + Editor:GetNoteSlideBodyX(nid, segmentsCount - 1),
        Y = BeatToPoint(Editor:GetNoteBeat(nid, false)),
        Beat = Editor:GetNoteBeat(nid, false)
    }
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

---@param p1 any 始点
---@param p2 any 終点
---@param p any 制御点
---@param t any
---@return table
function Bezier(p1, p2, p, t)
    local x = (1 - t) ^ 2 * p1.X + 2 * (1 - t) * t * p.X + t ^ 2 * p2.X
    local y = (1 - t) ^ 2 * p1.Y + 2 * (1 - t) * t * p.Y + t ^ 2 * p2.Y
    return { x, y }
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
    SetParameters(nid)
end

------------------------------------------------------------
-- ドラッグ中
------------------------------------------------------------
function OnDragMove()
    if SelectedNote ~= nil then
        ControlPoint = {
            X = Editor:GetClickX(),
            Y = BeatToPoint(Editor:GetClickBeat())
        }

        Editor:ShowTip('(' .. ControlPoint.X .. ', ' .. ControlPoint.Y .. ')')
        Editor:StartBatch()
        Editor:DeleteNoteSlideBody(SelectedNote)

        local totalBeat = Editor:BeatMinus(P2.Beat, P1.Beat)
        local segmentsCount = math.floor(BeatToPoint(totalBeat) * DevideLevel)

        for seg = 1, segmentsCount do
            local t = Bezier(P1, P2, ControlPoint, seg / segmentsCount)

            -- Preview
            local mod = Editor:AddSprite('m-' .. SelectedNote .. '-' .. seg, 'editor-wipe-ex.png')
            mod.Width = math.floor(100 * Editor:GetNoteWidth(SelectedNote) / 256)
            mod.Height = 20
            mod.Beat = PointToBeat(t[2])
            mod.X = math.floor(100 * t[1] / 256)
        end

        Editor:SelectNote(-1)
        Editor:FinishBatch()
    end
end

------------------------------------------------------------
-- ドラッグ終了
------------------------------------------------------------
function OnDragEnd()
    if SelectedNote ~= nil then
        ControlPoint = {
            X = Editor:GetClickX(),
            Y = BeatToPoint(Editor:GetClickBeat())
        }

        Editor:ShowTip('')
        Editor:StartBatch()
        Editor:DeleteNoteSlideBody(SelectedNote)

        local totalBeat = Editor:BeatMinus(P2.Beat, P1.Beat)
        local segmentsCount = math.floor(BeatToPoint(totalBeat) * DevideLevel)

        local headNote = Editor:AddNote(NoteType.Wipe)
        Editor:SetNoteBeat(headNote, P1.Beat, true)
        Editor:SetNoteX(headNote, P1.X)
        Editor:SetNoteWidth(headNote, Editor:GetNoteWidth(SelectedNote))

        for seg = 1, segmentsCount do
            local t = Bezier(P1, P2, ControlPoint, seg / segmentsCount)

            local addedNote = Editor:AddNote(NoteType.Wipe)
            Editor:SetNoteBeat(addedNote, PointToBeat(t[2]), true)
            Editor:SetNoteX(addedNote, math.floor(t[1]))
            Editor:SetNoteWidth(addedNote, Editor:GetNoteWidth(SelectedNote))

            Editor:RemoveModule('m-' .. SelectedNote .. '-' .. seg)
        end

        Editor:DeleteNote(SelectedNote)

        Editor:FinishBatch()
    end
end
