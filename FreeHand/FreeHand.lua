-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-09-14
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'FreeHand'
PluginMode = 7
PluginType = 2
PluginRequire = '6.4.2'
PluginIcon = 'FreeHand.png'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local Head = nil
local Segments = {}

function Reset()
    Head = nil
    Segments = {}
end

function AddPreviewModule(index, clickX, clickBeat)
    local mod = Editor:AddSprite('m-free-preview-' .. index, 'editor-freehand-preview.png')
    mod.Beat = clickBeat
    mod.X = math.floor(100 * clickX / 256)
end

------------------------------------------------------------
-- プラグイン起動時
------------------------------------------------------------
function OnActive()
    Reset()
end

------------------------------------------------------------
-- プラグイン終了時
------------------------------------------------------------
function OnDeactive()
    Reset()
end

------------------------------------------------------------
-- ドラッグ開始時
------------------------------------------------------------
function OnDragStart()
    Head = {
        X = Editor:GetClickX(),
        Y = BeatToPoint(Editor:GetClickBeat()),
        Beat = Editor:GetClickBeat()
    }
    AddPreviewModule(0, Head.X, Head.Beat)
end

------------------------------------------------------------
-- ドラッグ中
------------------------------------------------------------
function OnDragMove()
    local clickX = Editor:GetClickX()
    local clickY = BeatToPoint(Editor:GetClickBeat())

    local hand = Editor:AddSprite('m-hand', 'editor-hand.png')
    hand.Beat = Editor:GetClickBeatFree()
    hand.X = math.floor(100 * clickX / 256)

    if clickY > Head.Y then
        if #Segments == 0 then
            Segments[1] = {
                X = clickX,
                Y = clickY,
                Beat = Editor:GetClickBeat()
            }
            AddPreviewModule(1, Segments[1].X, Segments[1].Beat)
        else
            if clickY > Segments[#Segments].Y then
                Segments[#Segments + 1] = {
                    X = clickX,
                    Y = clickY,
                    Beat = Editor:GetClickBeat()
                }
                AddPreviewModule(#Segments, Segments[#Segments].X, Segments[#Segments].Beat)
            end
        end
    end
end

------------------------------------------------------------
-- ドラッグ終了
------------------------------------------------------------
function OnDragEnd()
    local n = Editor:AddNote(NoteType.Slide)
    Editor:SetNoteBeat(n, Head.Beat, true)
    Editor:SetNoteX(n, Head.X)
    Editor:SetNoteWidth(n, 50)

    for seg = 1, #Segments do
        Editor:AddNoteSlideBody(n, PointToBeat(Segments[seg].Y - Head.Y))
        Editor:SetNoteSlideBodyX(n, seg - 1, math.floor(Segments[seg].X - Head.X))
    end

    for seg = 0, #Segments do
        Editor:RemoveModule('m-free-preview-' .. seg)
    end
    Editor:RemoveModule('m-hand')
    Reset()
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