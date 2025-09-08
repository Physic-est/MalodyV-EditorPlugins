-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-08-29
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'Join Slides'
PluginMode = 7
PluginType = 0
PluginRequire = '6.4.2'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}


function Run()
    local selectedNotes = Editor:GetSelectNotes()
    local notesCount = selectedNotes == nil and 0 or selectedNotes.Length
    local mainSlide = nil
    local segmentsList = {}

    if notesCount < 2 then
        Editor:ShowMessage('Please select two or more slide notes.')
        return
    end

    mainSlide = selectedNotes[0]
    for i = 0, notesCount - 1 do
        local note = selectedNotes[i]
        if Editor:GetNoteType(note) ~= NoteType.Slide then
            Editor:ShowMessage('Only slide notes can be joined.')
            return
        end
        if BeatToPoint(Editor:GetNoteBeat(note, true)) < BeatToPoint(Editor:GetNoteBeat(mainSlide, true)) then
            mainSlide = note
        end
    end

    Editor:StartBatch()

    for i = 0, notesCount - 1 do
        local note = selectedNotes[i]
        local segmentsCount = Editor:GetNoteSlideBodyCount(note)
        -- セグメント情報を保存
        for seg = 0, segmentsCount - 1 do
            table.insert(segmentsList, {
                X = Editor:GetNoteX(note) + Editor:GetNoteSlideBodyX(note, seg),
                Y = BeatToPoint(Editor:GetNoteBeat(note, true)) + BeatToPoint(Editor:GetNoteSlideBodyBeat(note, seg))
            })
        end
        -- メインのスライド以外は始点の情報も保存
        if note ~= mainSlide then
            table.insert(segmentsList, {
                X = Editor:GetNoteX(note),
                Y = BeatToPoint(Editor:GetNoteBeat(note, true))
            })
            Editor:DeleteNote(note)
        else
            Editor:DeleteNoteSlideBody(mainSlide)
        end
    end

    -- 保存したセグメント情報をのY座標順（Beat順）で並び替え
    table.sort(segmentsList, function(a, b) return a.Y < b.Y end)

    local segIndex = 0
    for i = 1, #segmentsList do
        local seg = segmentsList[i]
        if i > 1 and (seg.Y <= segmentsList[i - 1].Y) then
            -- セグメントが重複している場合はスキップ
        else
            Editor:AddNoteSlideBody(mainSlide, PointToBeat(seg.Y - BeatToPoint(Editor:GetNoteBeat(mainSlide, true))))
            Editor:SetNoteSlideBodyX(mainSlide, segIndex, seg.X - Editor:GetNoteX(mainSlide))
            segIndex = segIndex + 1
        end
    end

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
