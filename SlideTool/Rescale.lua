-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2026-08-30
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'ReScale'
PluginMode = 7
PluginType = 2
PluginRequire = '6.4.2'
PluginIcon = 'ReScale.png'

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

local MinScale = 0.05   -- 潰れ／反転を防ぐ最小倍率

local P1 = nil                  -- 頭（固定点）
local OrigTailY = nil           -- 元の尻尾Y（倍率算出の基準）
local OriginalSegments = {}     -- 起動時のセグメント形状（不変）
local GripY = nil               -- 現在のGrip（尻尾）Y

local SelectedNote = nil
local SelectedPoint = nil

function Reset()
    P1 = nil
    OrigTailY = nil
    OriginalSegments = {}
    GripY = nil
    SelectedNote = nil
    SelectedPoint = nil
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

-- 現在のGrip位置から倍率を算出
function CurrentScale()
    local span = OrigTailY - P1.Y
    if span <= 0 then return 1 end
    local k = (GripY - P1.Y) / span
    if k < MinScale then k = MinScale end
    return k
end

------------------------------------------------------------
-- パラメータ収集
------------------------------------------------------------
function SetParameters()
    -- 頭（固定点）
    P1 = {
        X = Editor:GetNoteX(SelectedNote),
        Y = BeatToPoint(Editor:GetNoteBeat(SelectedNote, true)),
    }

    -- セグメント形状を保存（頭からのY・Xを絶対座標で）
    OriginalSegments = {}
    local segmentsCount = Editor:GetNoteSlideBodyCount(SelectedNote)
    for i = 0, segmentsCount - 1 do
        OriginalSegments[i + 1] = {
            X = Editor:GetNoteX(SelectedNote) + Editor:GetNoteSlideBodyX(SelectedNote, i),
            Y = P1.Y + BeatToPoint(Editor:GetNoteSlideBodyBeat(SelectedNote, i)),
        }
    end

    -- 元の尻尾Y（＝最終セグメント）
    OrigTailY = BeatToPoint(Editor:GetNoteBeat(SelectedNote, false))
    GripY = OrigTailY
end

------------------------------------------------------------
-- Y方向スケールを適用（OriginalSegmentsから再構築）
------------------------------------------------------------
function ApplyScale()
    local k = CurrentScale()

    Editor:StartBatch()
    Editor:DeleteNoteSlideBody(SelectedNote)

    for i = 1, #OriginalSegments do
        local seg = OriginalSegments[i]
        local newY = P1.Y + (seg.Y - P1.Y) * k
        Editor:AddNoteSlideBody(SelectedNote, PointToBeat(newY - P1.Y))
        Editor:SetNoteSlideBodyX(SelectedNote, i - 1, math.floor(seg.X - P1.X))
    end

    Editor:FinishBatch()
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
    SetParameters()
end

------------------------------------------------------------
-- プラグイン終了時
------------------------------------------------------------
function OnDeactive()
    Editor:ShowTip('')
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
    if SelectedNote == nil then return end

    local offsetY = BeatToPoint(Editor:MakeBeat(0, 1, 8))
    local clickY = BeatToPoint(Editor:GetClickBeat())

    SelectedPoint = nil

    -- Gripライン（横一直線）はY方向の近さだけで掴めるようにする
    if GripY - offsetY <= clickY and clickY <= GripY + offsetY then
        SelectedPoint = PointType.GripPoint
    end
end

------------------------------------------------------------
-- ドラッグ中
------------------------------------------------------------
function OnDragMove()
    if SelectedNote ~= nil and SelectedPoint == PointType.GripPoint then
        -- Gripを掴んだ位置へ移動（最小倍率位置より上には行かせない）
        GripY = BeatToPoint(Editor:GetClickBeat())
        local minGripY = P1.Y + (OrigTailY - P1.Y) * MinScale
        if GripY < minGripY then GripY = minGripY end

        ApplyScale()

        Editor:ShowTip('x' .. string.format('%.3f', CurrentScale()))
    end
end

------------------------------------------------------------
-- ドラッグ終了
------------------------------------------------------------
function OnDragEnd()
    if SelectedNote ~= nil and SelectedPoint == PointType.GripPoint then
        Editor:ShowTip('')
        SelectedPoint = nil
    end
end
